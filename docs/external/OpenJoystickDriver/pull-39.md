# PR #39: Add USB endpoints for Xbox Wolverine V3 TE (Wired, inputs resolving)

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/pull/39
- **State:** OPEN
- **Draft:** False
- **Author:** multision
- **Created:** 2026-09-24T00:23:23Z
- **Updated:** 2026-09-24T01:13:51Z
- **Closed:** —
- **Merged:** —

## Description

0x81/0x01, successful handshake, LED comes on, and all buttons/sticks/triggers/D-pad work. The issue was the device profile selecting the wrong endpoints. Resolves https://github.com/xsyetopz/OpenJoystickDriver/issues/14

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Bug Fixes**
  * Added USB endpoint configuration for a supported Xbox One controller, improving its USB connection handling.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->

## Files

- `Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json` (+7/-1, MODIFIED)

## Commits

- `ab39786ab1d4` Add USB endpoints for Xbox Wolverine V3 TE (Wired, inputs resolving))

## Conversation

### agentscanapp[bot] — 2026-09-24T00:23:33Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/39#issuecomment-5805187007)

<!-- agentscanapp-bot -->
### Insufficient data

Not enough activity yet to make a reliable assessment.

[View full analysis →](https://agentscan.tools/user/multision)

<sub>This is an automated analysis by [AgentScan](https://agentscan.tools)</sub>

### coderabbitai[bot] — 2026-09-24T00:23:42Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/39#issuecomment-5805188285)

<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- review_stack_entry_start -->

<a href="https://app.coderabbit.ai/change-stack/xsyetopz/OpenJoystickDriver/pull/39"><img src="https://storage.googleapis.com/coderabbit_public_assets/review-stack-in-coderabbit-ui-dark.svg?v=2" alt="Review in Change Stack →" width="220" height="32"></a>

Navigate logical layers of code changes, visualize relationships, and explore their blast radius.

<!-- review_stack_entry_end -->
<!-- recent_review_start -->

No actionable comments were generated in the recent review. 🎉

<details>
<summary>ℹ️ Recent review info</summary>

<details>
<summary>⚙️ Run configuration</summary>

**Configuration used**: Organization UI

**Review profile**: CHILL

**Plan**: Advanced

**Run ID**: `6f215ee6-6aa4-46a2-af40-f79e1603411f`

</details>

<details>
<summary>📥 Commits</summary>

Reviewing files that changed from the base of the PR and between d43199315ce713cc8c5f543077cf5da616b61efb and ab39786ab1d4d404a501aaeac36a426f6a70e6e0.

</details>

<details>
<summary>📒 Files selected for processing (1)</summary>

* `Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json`

</details>

**Included review availability:** Your plan provides up to 1 included review per hour; 0 remain after this review.

</details>

---



<!-- recent_review_end -->
<!-- walkthrough_start -->

<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

The controller profile for the Razer Wolverine V3 Tournament Edition adds USB endpoint declarations for input endpoint 129 and output endpoint 1.

### Changes

**Controller Profile**

|Layer / File(s)|Summary|
|---|---|
|**USB endpoint declarations** <br> `Sources/OpenJoystickDriverKit/Resources/Controllers/1532/1532-0a43.json`|The profile now declares input endpoint 129 and output endpoint 1.|

<!-- change_assessment_start -->
**Priority:** ➖ Normal

**Estimated code review effort:** 1 (Trivial) | ~5 minutes

<!-- change_assessment_commit:"ab39786ab1d4d404a501aaeac36a426f6a70e6e0" -->
**Change:** Bug fix · **Severity of issue fixed:** Medium
<!-- change_assessment_end -->

**Suggested reviewers:** `xsyetopz`

</details>

<!-- walkthrough_end -->
<!-- final_review_risk_start -->
**Merge Risk:** _⚪ Minimal_ · up to `ab397`
<!-- final_review_risk_coverage:{"sourceCommitId":"ab39786ab1d4d404a501aaeac36a426f6a70e6e0","coveredCommitId":"ab39786ab1d4d404a501aaeac36a426f6a70e6e0","kind":"reviewed"} -->

The profile adds endpoint overrides that fit the decoder contract and are selected by the catalog. No actionable merge-blocking risk is evident.
<!-- final_review_risk_end -->
<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 5</summary>

<details>
<summary>✅ Passed checks (5 passed)</summary>

|         Check name         | Status   | Explanation                                                                                                                                                                                               |
| :------------------------: | :------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|      Description Check     | ✅ Passed | Check skipped - CodeRabbit’s high-level summary is enabled.                                                                                                                                               |
|         Title check        | ✅ Passed | The title clearly identifies the main change: adding USB endpoints for the Xbox Wolverine V3 TE. It also states the resulting input resolution.                                                           |
|     Linked Issues check    | ✅ Passed | Issue [`#14`] requests a USB GIP profile for VID:PID 1532:0A43. The reviewed profile defines USB transport, GIP `xboxOne`, input endpoint `129` (`0x81`), and output endpoint `1` (`0x01`). The PR summary… |
| Out of Scope Changes check | ✅ Passed | The available whole-PR summary identifies one change in the 1532:0A43 controller profile. The change adds the endpoint declarations required by [`#14`]. No unrelated product, protocol, or repository cha… |
|     Docstring Coverage     | ✅ Passed | No functions found in the changed files to evaluate docstring coverage. Skipping docstring coverage check. Docstring coverage is scoped to functions touched by this diff. Analyzed 0 functions across 0… |

</details>

</details>

<!-- pre_merge_checks_walkthrough_end -->
<!-- finishing_touch_checkbox_start -->

<details>
<summary>✨ Finishing Touches</summary>

<details open>
<summary>🧪 Generate unit tests (beta)</summary>

- [ ] <!-- {"checkboxId": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "radioGroupId": "utg-output-choice-group-unknown_comment_id"} --> Create a new PR

</details>
<details open>
<summary>✨ Simplify code</summary>

- [ ] <!-- {"checkboxId": "f120d606-b0e2-4b7d-8316-181794555b43", "radioGroupId": "simplify-output-choice-group-unknown_comment_id"} --> Create a new PR

</details>

</details>

<!-- finishing_touch_checkbox_end -->
<!-- tips_start -->

---

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=xsyetopz/OpenJoystickDriver&utm_content=39)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>


<!-- poem_footer_start -->
<sub>A rabbit checks the USB line,<br>Input endpoint joins the sign.<br>Output finds its numbered place,<br>The profile records the case.<br>One small hop, the config’s done.</sub>
<!-- poem_footer_end -->

<sub>Comment `@coderabbitai help` to get the list of available commands.</sub>

<!-- tips_end -->

### multision — 2026-09-24T00:28:12Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/39#issuecomment-5805232111)

Tested on Apple Silicon using a MacBook Air M1 running macOS Tahoe 26.5.2 with a Razer Wolverine V3 Tournament Edition (`1532:0A43`).

Before this change, OpenJoystickDriver detected the controller as a GIP device, but it was using the wrong USB endpoints. Because of that, the controller would never complete the handshake. The LED status indicator stayed off, and no input was received from buttons, sticks, triggers, or the D-pad.

The controller’s actual GIP interface uses:

* Interface `0`
* IN endpoint `0x81`
* OUT endpoint `0x01`

After updating the device profile to use those endpoints, the standard Xbox One GIP startup sequence completed successfully. The controller powered on normally, the LED status indicator came on, and input started reporting immediately.

I tested the full set of normal controls through the OJD diagnostic tool, including face buttons, bumpers, triggers, both analog sticks, stick clicks, D-pad, View/Menu, and the Xbox button. Everything I tested responded correctly.

So far, this change fully resolves the startup/handshake and input issue on my Wolverine V3 Tournament Edition.

### multision — 2026-09-24T01:13:51Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/pull/39#issuecomment-5805679442)

This may not fully resolve issue #14, since I also my enrollment with the developer program expired. It may need to be combined with some of the changes in #14 to fully & properly work.

## Reviews

_No reviews._

## Inline review comments

_No inline review comments._

## Patch

[Full patch](pull-39.patch)
