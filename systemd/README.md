# flowref autoresearch systemd units

User-level timer + service for the karpathy/autoresearch-style training loop.

## Install

```bash
cp systemd/flowref-autoresearch.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now flowref-autoresearch.timer
```

## Watch

```bash
journalctl --user -fu flowref-autoresearch.service
```

## What it does

Every 5 minutes (FLOWREF_RESEARCH_BUDGET=600, wall-clock per run):
1. Materializes training-set binaries under /tmp/flowref-autorun-<RUN_ID>/
2. Runs the strict equivalence oracle + unsafe C compile check on all 61 fixtures
3. Writes Parquet snapshots (training_manifest, results, summary, hypotheses)
4. If SOUNDNESS=0: `git add -u && git commit` with the run ID and proven count
5. If SOUNDNESS>0: logs REJECT, exits non-zero, no commit

The timer fires next run 5 minutes after the previous run completes
(OnUnitActiveSec=5min), so concurrent runs never overlap.
