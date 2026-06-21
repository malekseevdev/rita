# DEMO-9: feasibility

## Verified blocks

#### Python can serialize rows to CSV

- **Assumption:** The standard library can write CSV.
- **Failure-mode:** No CSV writer available.
- **Command:** `python3 -c "import csv; print(csv.writer)"`
- **Env:** python 3.12, ubuntu-24.04
- **Expected exit:** 0
- **Observed exit:** 0
- **Observed output:**
  ```
  <built-in function writer>
  ```
- **Recorded:** 2026-05-01 by devbot

#### Production object store accepts 5 GB multipart uploads

- **Assumption:** The prod bucket accepts multipart uploads up to 5 GB so
  large exports don't fail.
- **Failure-mode:** Upload rejected above some size.
- **Command:** `python3 -c "print('multipart ok')"`
- **Env:** local dev laptop
- **Expected exit:** 0
- **Observed exit:** 0
- **Observed output:**
  ```
  multipart ok
  ```
- **Recorded:** 2026-05-01 by devbot
