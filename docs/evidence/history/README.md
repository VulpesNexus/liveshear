# Earlier runs, kept for the record

These were measured against builds that are not the one in the current release. They are here because they are worth reading, not because they describe the plugin you can download — and the date in each filename is the claim this folder makes about them.

*tools/make-release.ps1* checks that every file in *docs/evidence/* postdates the build record and deliberately does not look in here. That is the whole point of the folder: a file whose date is in its name states what it is where a reader sees it, in the path, rather than in an exemption list that only the release script reads. The exemption list is for files that do not describe the binary at all, and it is short on purpose.

The probes that produced these still write to *docs/evidence/*. Re-running one puts a fresh file in the gated folder, where it is checked normally; nothing is overwritten here.

| file | what it is |
| --- | --- |
| *crash-control-2026-09-13.txt* | Three runs of forty create/close cycles with the plugin uninstalled, completing 9, 32, and 40. Superseded by *crash-arm-a-2026-09-14.txt*, which asks the same question at six trials of sixty cycles. |
| *crash-arm-a-2026-09-14.txt* | Arm A of the crash comparison: six trials of up to sixty create/close cycles with the plugin uninstalled, measured against 0.1.1. Not re-run for 0.1.2 or 0.1.3, whose only changes are the dialog and the About window, which no trial opens. Cited by *docs/RELEASE_READINESS.md* and *LIVE_SHEAR_INVESTIGATION.md*. |
| *crash-ab-2026-09-14.tsv*, *crash-ab-2026-09-14.txt* | Arms B and C of the same comparison, the plugin loaded but unused and the effect applied every cycle, measured against 0.1.1 and not re-run for 0.1.2 or 0.1.3 for the same reason. Cited by *docs/RELEASE_READINESS.md*, *LIVE_SHEAR_INVESTIGATION.md*, and the test matrix, which labels the section as measured against 0.1.1. |
| *crash-probe-2026-09-13.txt* | The first look at the crash, before there were arms to compare. Cited by nothing. |
| *behavior-2026-09-13.txt* | Host behavior recorded during the investigation. Cited by *LIVE_SHEAR_INVESTIGATION.md*. |
| *latent-shear-probe-2026-09-12.txt* | Whether the host carries a latent shear of its own. Cited by *LIVE_SHEAR_INVESTIGATION.md*. |
| *missing-plugin-warning-2026-09-13.png* | Illustrator's warning when a document is opened without *LiveShear.aip* installed. Captured by hand; the missing-plugin probe does not take this screenshot, so it does not refresh itself. |
