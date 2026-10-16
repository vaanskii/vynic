# POS-02 Windows recovery and test release

The existing Windows 11 ARM Parallels VM at 10.10.10.9 is updated to POS 1.0.14 / release 15 and left running at PIN login. Signed feed, all 24 installed artifact files, source/build receipt, startup SUCCESS and visible version are verified.

Seven product suites pass 96 checks. The standalone runner has 39 passes / one Windows path failure; the physical entry is skipped. The aggregate is failed and POS-02 remains NOT_DONE/uncommitted. This runner is not shipped in the installed product. No physical jobs, security/trust changes, key rotation, new tool installs or unrelated WIP edits occurred.

Proof and archived logs record intermediate handoff failures and their isolated corrections. Existing source/runner proof kits remain immutable. Migration preserves all 23 original data files byte-for-byte. After launch, original files remain present at the same path; active Hive locks prevent a complete post-launch hash comparison.

Windows artifact: existing local release root/public/artifacts/pos-4534e35e68c19a59871c04476f03dc13205d7f705e83209253b2fd693a8f6fb0.zip. Prepared source ZIP: pos-source-0bf6dd5beeb9f4ff9533aea5babaae03f27790f56471099a1184cf6e27994db7.zip.
