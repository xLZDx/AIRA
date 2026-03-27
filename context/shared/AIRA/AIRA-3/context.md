## Issue
- **Key:** AIRA-3
- **Summary:** Implement Two-Factor Authentication (2FA) for User Login
- **Type:** Story
- **Status:** In Progress
- **Priority:** Highest
- **Created:** 2026-03-11
- **Last Updated:** 2026-03-11

## Description
## Overview
As a security-conscious user, I want to enable two-factor authentication on my account so that my data is protected even if my password is compromised.

The system must support TOTP-based 2FA (Google Authenticator, Authy) and SMS-based verification as a fallback.

## Business Context
Compliance requirement for SOC2 certification. All administrator accounts MUST have 2FA enabled by default. Regular users can opt-in.

## Acceptance Criteria
| **ID** | **Scenario** | **Expected Result** |
| --- | --- | --- |
| AC-01 | User navigates to Security Settings | 2FA setup option is visible with clear instructions |
| AC-02 | User scans QR code with authenticator app | TOTP secret is generated and bound to the account |
| AC-03 | User enters valid 6-digit TOTP code | 2FA is activated, confirmation email sent |
| AC-04 | User enters invalid TOTP code | Error message displayed, account not locked after 3 attempts |
| AC-05 | User with 2FA enabled logs in | Prompted for TOTP code after password entry |
| AC-06 | User enters correct TOTP at login | Access granted, session created |
| AC-07 | User selects SMS fallback | SMS sent to registered phone number within 30 seconds |
| AC-08 | Admin account created without 2FA | System forces 2FA setup on first login |

## Technical Notes
- Backend: `POST /api/v2/auth/2fa/setup`, `POST /api/v2/auth/2fa/verify`
- Use the `speakeasy` library for TOTP generation
- QR code rendered via `qrcode` npm package
- SMS via existing Twilio integration (see AIRA-xxx for SMS service)
- Rate limit: max 5 verification attempts per 10-minute window

## Out of Scope
- Hardware key support (YubiKey) — planned for Phase 2
- Biometric authentication

## Acceptance Criteria
- ID: AC-01 | Scenario: User navigates to Security Settings | Expected Result: 2FA setup option is visible with clear instructions
- ID: AC-02 | Scenario: User scans QR code with authenticator app | Expected Result: TOTP secret is generated and bound to the account
- ID: AC-03 | Scenario: User enters valid 6-digit TOTP code | Expected Result: 2FA is activated, confirmation email sent
- ID: AC-04 | Scenario: User enters invalid TOTP code | Expected Result: Error message displayed, account not locked after 3 attempts
- ID: AC-05 | Scenario: User with 2FA enabled logs in | Expected Result: Prompted for TOTP code after password entry
- ID: AC-06 | Scenario: User enters correct TOTP at login | Expected Result: Access granted, session created
- ID: AC-07 | Scenario: User selects SMS fallback | Expected Result: SMS sent to registered phone number within 30 seconds
- ID: AC-08 | Scenario: Admin account created without 2FA | Expected Result: System forces 2FA setup on first login

## Comments (8 total)
**Comment #1** by *Administrator* (2026-03-11):
> The speakeasy library supports window tolerance via the 'window' parameter. We should set it to 0 for strict mode per the SOC2 requirement. Default is 1 (allows T-1 and T+1 codes). See: https://github.com/speakeasyjs/speakeasy#totp-verification

**Comment #2** by *Administrator* (2026-03-11):
> UX team confirmed: the QR code setup flow should follow the Google Authenticator standard layout. We'll show the QR code, a manual entry key below it, and a verification input. Mockups attached to the design ticket.

**Comment #3** by *Administrator* (2026-03-11):
> SMS fallback implementation depends on the Twilio rate limits. We currently have 100 SMS/min on the Growth plan. For the initial release, let's cap SMS 2FA to 3 attempts per hour per account to stay safe.

**Comment #4** by *Administrator* (2026-03-11):
> QA note: we need to test timezone edge cases for TOTP. Users traveling across timezones should still be able to authenticate as long as their device clock is synced (within 30 seconds drift).

**Comment #5** by *Administrator* (2026-03-11):
> The speakeasy library supports window tolerance via the "window" parameter. We should set it to 0 for strict mode per the SOC2 requirement. Default is 1 which allows T-1 and T+1 codes. See: https://github.com/speakeasyjs/speakeasy#totp-verification

**Comment #6** by *Administrator* (2026-03-11):
> UX team confirmed: the QR code setup flow should follow the Google Authenticator standard layout. We will show the QR code, a manual entry key below it, and a verification input. Mockups attached to the design ticket.

**Comment #7** by *Administrator* (2026-03-11):
> SMS fallback implementation depends on the Twilio rate limits. We currently have 100 SMS/min on the Growth plan. For the initial release, let us cap SMS 2FA to 3 attempts per hour per account to stay safe.

**Comment #8** by *Administrator* (2026-03-11):
> QA note: we need to test timezone edge cases for TOTP. Users traveling across timezones should still be able to authenticate as long as their device clock is synced within 30 seconds drift.


## Direct Dependencies
| Key | Relationship | Status | Summary | Context Link |
|-----|-------------|--------|---------|-------------|
| AIRA-10 | Blocks (inward) | In Progress | 2FA TOTP verification accepts expired codes from previous 30-second window | `dependencies/AIRA-10/context.md` |
| AIRA-7 | Blocks (inward) | Done | Implement Role-Based Access Control (RBAC) Admin Panel | `dependencies/AIRA-7/context.md` |

## All Linked Issues (2 total)
| Key | Type | Status | Summary |
|-----|------|--------|---------|
| AIRA-7 | Story | Done | Implement Role-Based Access Control (RBAC) Admin Panel |
| AIRA-10 | Bug | In Progress | 2FA TOTP verification accepts expired codes from previous 30-second window |

## Existing Coverage (TestRail)
- Status: Not Checked (use -WithCoverage to include)
- Direct cases: -
- Related cases: -

## References & Links
- Jira: [AIRA-3](http://jira.localhost:8080//browse/AIRA-3)
- Confluence:
  - [Security Standards and Compliance Requirements](http://confluence.localhost:8090/spaces/AIRA/pages/1245189/Security+Standards+and+Compliance+Requirements)
- Attachments: 3 file(s) (downloaded: 3)
  - `2fa_auth_flow.svg` (image/svg+xml, downloaded)
  - `2fa_security_requirements.txt` (text/plain, downloaded)
  - `compliance_checklist.pdf` (application/pdf, downloaded)

## Attachment Extractions
<!-- ATTACHMENT_ANALYSIS_PLACEHOLDER -->
*Extracted data from 3 attachment(s) saved to `sources/attachment_extractions.json` for AI analysis.*
*The AI agent will analyze and summarize each file below during the analysis phase.*

- **2fa_auth_flow.svg** (SVG Diagram, 7.7 KB) - extraction: svg_text_elements
- **2fa_security_requirements.txt** (Text, 2.2 KB) - extraction: utf8_text_read
- **compliance_checklist.pdf** (PDF Document, 2.6 KB) - extraction: pdf_text_scan

## Concerns / Known Bugs (NOT analyzed as requirements)
- AIRA-10: 2FA TOTP verification accepts expired codes from previous 30-second window
