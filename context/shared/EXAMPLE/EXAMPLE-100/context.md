## Issue
- **Key:** EXAMPLE-100
- **Summary:** Add User Profile Settings Page
- **Type:** Story
- **Status:** In Progress
- **Priority:** High
- **Created:** 2026-01-15
- **Last Updated:** 2026-02-08

## Description
Build a new User Profile Settings page that allows users to update their display name,
email notification preferences, and avatar. The page should be accessible from the
main navigation menu under "My Account".

### Scope
* New .NET page replicating the wireframe provided by UX.
* Backend API endpoint to persist profile changes.
* Email notification opt-in/opt-out toggle.

## Acceptance Criteria
| ID | Scenario | Expected Result |
|----|----------|-----------------|
| AC-01 | User navigates to My Account → Profile | Profile settings page loads |
| AC-02 | User updates display name and clicks Save | Name saved, confirmation shown |
| AC-03 | User toggles email notifications off | No further email notifications sent |
| AC-04 | User uploads a new avatar image | Avatar updated across all pages |

## Comments (2 total)

**#1** — Jane Smith (2026-01-20):
> UX wireframes attached. Please ensure the avatar upload supports JPG and PNG only, max 2 MB.

**#2** — Bob Lee (2026-02-01):
> Backend API endpoint will be POST /api/v2/user/profile. Schema TBD by backend team.

## Direct Dependencies
| Key | Relationship | Status | Summary | Context Link |
|-----|-------------|--------|---------|-------------|
| EXAMPLE-90 | Blocks (outward) | Done | Implement user authentication flow | dependencies/EXAMPLE-90/context.md |
| EXAMPLE-110 | Relates (outward) | In Progress | Email notification service refactor | dependencies/EXAMPLE-110/context.md |

## All Linked Issues (3 total)
| Key | Type | Status | Summary |
|-----|------|--------|---------|
| EXAMPLE-90 | Story | Done | Implement user authentication flow |
| EXAMPLE-110 | Story | In Progress | Email notification service refactor |
| EXAMPLE-115 | Bug | Open | Avatar upload fails on Safari 16 |

## Existing Coverage (TestRail)

**Project:** EXAMPLE App (ID 99) | **Run:** [R12345 — User Profile Settings](https://testrail.example.com/index.php?/runs/view/12345)
**Run Status:** In Progress | **Analyzed:** 2026-02-08

| Metric | Value |
|--------|-------|
| Total Cases in Run | 8 |
| ✅ Passed | 5 (62%) |
| ❌ Failed | 1 (13%) |
| ⬜ Untested | 2 (25%) |

### Cases in Run
| Case ID | Title | Status |
|---------|-------|--------|
| C50001 | Profile page loads for authenticated user | ✅ Passed |
| C50002 | Unauthorized user redirected to login | ✅ Passed |
| C50003 | Display name updates successfully | ✅ Passed |
| C50004 | Email toggle saves preference | ❌ Failed |
| C50005 | Avatar upload accepts JPG | ✅ Passed |
| C50006 | Avatar upload accepts PNG | ✅ Passed |
| C50007 | Avatar upload rejects files > 2 MB | ⬜ Untested |
| C50008 | Concurrent profile edits handled gracefully | ⬜ Untested |

### Attention Items
- **1 Failed:** C50004 (Email toggle) — notification service endpoint returning 500; blocked by EXAMPLE-110
- **2 Untested:** C50007 (File size limit), C50008 (Concurrency)

## References & Links
- Jira: [EXAMPLE-100](https://jira.example.com/browse/EXAMPLE-100)
- Confluence: [User Profile Spec](https://wiki.example.com/pages/789012)
- Attachments: profile_wireframe.png (image/png, 340 KB)

## Concerns / Known Bugs (NOT analyzed as requirements)
- EXAMPLE-115: Avatar upload fails on Safari 16
