#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const cronRuntime = require("../src/lib/cron-runtime.js");
const { findWorkspaceRoot } = require("./workspace-root.cjs");

const TICK_INTERVAL_MS = 60_000;
const HEARTBEAT_INTERVAL_MS = 15_000;
const QUEUE_POLL_INTERVAL_MS = 2_000;
const agenticOsDir = cronRuntime.resolveAgenticOsRoot(
  process.env.AGENTIC_OS_DIR || findWorkspaceRoot(__dirname)
);
const command = process.argv[2] || "status";

function parseArgs(argv) {
  const args = { clientId: null, slug: null };
  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--client") {
      args.clientId = argv[index + 1] || null;
      index += 1;
      continue;
    }
    if (!args.slug) {
      args.slug = value;
    }
  }
  return args;
}

function isPidAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function formatStatus(status) {
  return [
    `runtime: ${status.runtime}`,
    `leader: ${status.leader}`,
    `leaderState: ${status.leaderState}`,
    `statusSummary: ${status.statusSummary}`,
    `ownershipReason: ${status.ownershipReason}`,
    `identifier: ${status.identifier || "none"}`,
    `pid: ${status.pid || "none"}`,
    `workspaceCount: ${status.workspaceCount}`,
    `heartbeatAt: ${status.heartbeatAt || "n/a"}`,
    `startCommand: ${status.startCommand}`,
    `stopCommand: ${status.stopCommand}`,
    `logsCommand: ${status.logsCommand}`,
  ].join("\n");
}

async function runServe() {
  const identifier = `daemon-${process.pid}`;
  const runtimePaths = cronRuntime.getRuntimePaths(agenticOsDir);
  cronRuntime.writeDaemonPid(agenticOsDir, process.pid);

  let tickHandle = null;
  let heartbeatHandle = null;
  let queueHandle = null;
  let isLeader = false;
  let lastSweepAt = null;
  let currentExecution = null;

  const cleanup = () => {
    if (tickHandle) clearInterval(tickHandle);
    if (heartbeatHandle) clearInterval(heartbeatHandle);
    if (queueHandle) clearInterval(queueHandle);
    cronRuntime.releaseRuntimeLeadership(agenticOsDir, identifier);
  };

  const tick = () => {
    const workspaceCount = cronRuntime.listWorkspaceDescriptors(agenticOsDir).length;
    if (!cronRuntime.hasActiveCronJobs(agenticOsDir)) {
      if (isLeader) {
        cronRuntime.releaseRuntimeLeadership(agenticOsDir, identifier);
        isLeader = false;
        lastSweepAt = null;
      }
      return;
    }

    const claim = cronRuntime.claimRuntimeLeadership(agenticOsDir, {
      runtime: "daemon",
      identifier,
      pid: process.pid,
      workspaceCount,
      lastSweepAt,
    });

    if (!claim) {
      isLeader = false;
      return;
    }

    isLeader = true;
    const now = new Date();
    const activeJobs = cronRuntime
      .listAllCronJobs(agenticOsDir)
      .filter((job) => job.active && job.prompt);

    if (lastSweepAt) {
      const previous = new Date(lastSweepAt);
      for (const job of activeJobs) {
        for (const missedAt of cronRuntime.getMissedFixedRuns(job.time, job.days, previous, now)) {
          cronRuntime.enqueueCronJob(agenticOsDir, job, {
            trigger: "scheduled",
            dedupeByMinute: true,
            activityLabel: "Queued — catch-up",
            scheduledFor: missedAt.toISOString(),
          });
        }
      }
    }

    for (const job of activeJobs) {
      if (!cronRuntime.matchesTime(now, job.time)) {
        continue;
      }

      cronRuntime.enqueueCronJob(agenticOsDir, job, {
        trigger: "scheduled",
        dedupeByMinute: true,
        activityLabel: "Queued — scheduled",
        scheduledFor: cronRuntime.toMinuteIso(now),
      });
    }

    lastSweepAt = now.toISOString();
    cronRuntime.refreshRuntimeHeartbeat(agenticOsDir, identifier, {
      runtime: "daemon",
      workspaceCount,
      lastSweepAt,
    });
  };

  const processQueuedCronTask = async () => {
    if (!isLeader || currentExecution) {
      return;
    }

    const db = cronRuntime.getDb(agenticOsDir);
    const task = db
      .prepare(
        `SELECT * FROM tasks
         WHERE status = 'queued'
           AND cronJobSlug IS NOT NULL
         ORDER BY createdAt ASC
         LIMIT 1`
      )
      .get();

    if (!task) {
      return;
    }

    currentExecution = cronRuntime.executeCronTask(agenticOsDir, task.id);
    try {
      await currentExecution;
    } catch (error) {
      console.error("[cron-daemon] Failed to execute queued cron task:", error);
    } finally {
      currentExecution = null;
    }
  };

  process.on("exit", cleanup);
  process.on("SIGTERM", () => {
    cleanup();
    process.exit(0);
  });
  process.on("SIGINT", () => {
    cleanup();
    process.exit(0);
  });

  tick();
  tickHandle = setInterval(tick, TICK_INTERVAL_MS);
  heartbeatHandle = setInterval(() => {
    if (!isLeader) return;
    cronRuntime.refreshRuntimeHeartbeat(agenticOsDir, identifier, {
      runtime: "daemon",
      lastSweepAt,
    });
  }, HEARTBEAT_INTERVAL_MS);
  queueHandle = setInterval(() => {
    processQueuedCronTask().catch((error) => {
      console.error("[cron-daemon] Queue poll failed:", error);
    });
  }, QUEUE_POLL_INTERVAL_MS);

  console.log(`[cron-daemon] Serving ${agenticOsDir} as ${identifier}`);
}

function startDaemon() {
  let status = cronRuntime.getManagedRuntimeStatus(agenticOsDir);
  if (status.runtime === "daemon" && status.pid && !isPidAlive(status.pid)) {
    cronRuntime.releaseRuntimeLeadership(agenticOsDir, status.identifier || "daemon");
    status = cronRuntime.getManagedRuntimeStatus(agenticOsDir);
  }

  if (status.leaderState === "active") {
    console.log(formatStatus(status));
    return;
  }

  if (status.runtime === "daemon" && status.pid && isPidAlive(status.pid)) {
    console.log(formatStatus(status));
    return;
  }

  const runtimePaths = cronRuntime.getRuntimePaths(agenticOsDir);
  fs.mkdirSync(runtimePaths.dataDir, { recursive: true });
  const logFd = fs.openSync(runtimePaths.logPath, "a");
  const child = spawn(process.execPath, [__filename, "serve"], {
    cwd: agenticOsDir,
    detached: true,
    stdio: ["ignore", logFd, logFd],
    windowsHide: true,
    env: {
      ...process.env,
      AGENTIC_OS_DIR: agenticOsDir,
    },
  });

  fs.closeSync(logFd);
  child.unref();
  console.log(`started daemon pid ${child.pid}`);
  console.log(`logs: ${runtimePaths.logPath}`);
}

function stopDaemon() {
  const status = cronRuntime.getManagedRuntimeStatus(agenticOsDir);
  const pid = status.pid || cronRuntime.readDaemonPid(agenticOsDir);

  if (pid && isPidAlive(pid)) {
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      // Ignore kill race.
    }
  }

  cronRuntime.releaseRuntimeLeadership(agenticOsDir, status.identifier || "daemon");
  cronRuntime.removeDaemonPid(agenticOsDir);
  console.log("stopped daemon");
}

function showStatus() {
  console.log(formatStatus(cronRuntime.getManagedRuntimeStatus(agenticOsDir)));
}

function showLogs() {
  const logPath = cronRuntime.getRuntimePaths(agenticOsDir).logPath;
  if (!fs.existsSync(logPath)) {
    console.log("(no daemon log)");
    return;
  }

  const lines = fs.readFileSync(logPath, "utf-8").split(/\r?\n/);
  console.log(lines.slice(-200).join("\n"));
}

async function runJob() {
  const args = parseArgs(process.argv);
  if (!args.slug) {
    throw new Error("Usage: cron-daemon.cjs run-job <job-slug> [--client <client-id>]");
  }

  const result = await cronRuntime.runCronJobNow(agenticOsDir, args.slug, args.clientId);
  console.log(
    JSON.stringify(
      {
        taskId: result.task.id,
        result: result.result,
        exitCode: result.exitCode,
        durationMs: result.durationMs,
      },
      null,
      2
    )
  );
}

async function main() {
  switch (command) {
    case "start":
      startDaemon();
      break;
    case "serve":
      await runServe();
      break;
    case "stop":
      stopDaemon();
      break;
    case "status":
      showStatus();
      break;
    case "logs":
      showLogs();
      break;
    case "run-job":
      await runJob();
      break;
    default:
      throw new Error(`Unknown command: ${command}`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
