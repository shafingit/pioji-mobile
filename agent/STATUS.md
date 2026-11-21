# Status — 18 Nov 2026

## Built

All screens in the spec exist and compile with zero analyzer issues:

- Splash, 3-page onboarding, sign in (with session-expired state), Terms and Privacy pages
- Tab shell with the gradient bottom bar (tablet: side rail)
- 17 Nov 2026: solid tab bar with a top border; server sorting and `garden_id` mark filter on lists; posting lists filtered by the courier buyer; grade picker limited to the garden's grades; arrival date locked without `samples.edit_arrival_date`; sample For (billing company) and outgoing party with filters; tasting (record scores 0–10, park/unpark, tasted/parked filters, tasting report under More); bulk bids (add many lots of one mark, set asking/max on many); Users (list, detail, add, edit, role, activate/deactivate) for `users.view`; role, phone and department on More; New offer / Allocate hidden without their permissions
- 18 Nov 2026: every dropdown, status, segment and status label comes from `GET /form-options` (no status enums or option lists left in the app; only the status tint is chosen in the app, in `statusTone`). Garden-driven grades, invoice prefixes, grade id and invoice type from `GET /gardens/{id}/options`. "Fill from lot" on sales (`lookup-lot`) and ex-factory (`lookup-lot`), "Fill from offer list" on bids (`search-offer-list`), garden info on sales (incharge, category, location), seller-filtered gardens on contracts, pending posting lists per buyer on courier, duplicate-sample warning (`check-duplicate-combination`, saves `parent_sample_id`). New form fields: offer FOR / OFR-SAS / currency / courier / AWR no / list date, sale garden / category / incharge, contract garden and item currency, ex-factory total weight, user department / offices / password confirmation
- 19 Nov 2026: batch testing (start with testers from `pocs`, score each sample C/T/S/B 0–100 per tester with colour shade, leaf grade, report and CH defect, save and next via `POST /batches/{id}/testing-session/scores`, results screen), batch status picker (`PATCH /batches/{id}/status`), batch and batch-samples CSV export, new batches through `create-from-selection` when unnamed, sample marking (`bulk-mark`, modes from `form-options` → `sample_bulk_mark_modes`) and send for retesting (`transfer`), Auto-allocate on Offered today, sample "Other" grade and prefix (`grade_custom`, `invoice_prefix_custom`), Upload sheets screen (bulk upload in the `form-options` → `sample_upload_formats` layouts, manual marking, both templates; CSV or Excel)
- Own look on both platforms (12 Nov 2026): no Cupertino, custom SVG icons, Inter, compact 56 px top bar, custom dialog / sheet / calendar / switch / spinner / pull-to-refresh
- Home: samples today (with the total), unbatched, open bids, ex-factory mismatches, an all-time sales card (value, kg, pending approval), quick actions, a checklist driven by real counts (now including sales waiting for approval), recent samples. Most counts come from one `GET /dashboard/summary` call
- Samples: list (status segments, arrival and mark filters, grouped by arrival date → mark → invoice, latest / earliest first), new and edit sample (2-of-3 weights, duplicate "save anyway"), detail with delete
- Batches: list, new batch (pick unbatched samples, 48 cap), auto-batch for a date, detail, edit (open/completed, notes), delete
- Offer lists: list (date/grade/type/mark filters, grouped by date → mark → invoice), new offer (override / re-offer on duplicates; up to 10 parties, each picked from buyers or typed), detail, edit, delete
- Offered today: day switcher, offer/sample tabs, single and multi-select buyer allocation
- Bid book: tabbed list grouped by mark, one line per lot (grade · invoice, ask, max bid, status), new/edit lot, detail with one-tap status change and delete
- Courier: list, new entry (buyer address prefill, barcode scanner, photo, posting lists), detail, edit, delete
- Contracts: list (cover row: date range and buyer; number on the detail), new contract with repeatable items and live totals, detail, edit, delete
- Sales register: list (pending / approved / rejected), new sale with live amount, detail, edit, delete. A sale split between buyers shows its total packages, kg and value
- Ex-factory: status summary tiles, list, CSV export + share, new bill (IGST / CGST+SGST with 5% fill), detail, edit, delete
- Buyer and seller pickers can add a new buyer or seller by name (`POST /buyers`, `POST /sellers`)
- Write paths tested 5 Nov 2026 and re-tested 7 and 9 Nov 2026 (create, edit, delete for every module; details in `docs/API_DOCS.md` → Write tests)
- Every detail screen loads by ID (`GET /{module}/{id}`): it shows the list copy at once, refreshes from the API, and works from a deep link
- Grade pickers load the garden's grades, else `GET /grades`
- More and Settings (theme, version, legal), sign out
- App ID `com.gitcs.pioji` on iOS and Android; launcher icons (two-leaf mark, light/dark, Android adaptive + monochrome) and native splash

## Verified

On 31 Oct 2026, signed in as admin: every list, lookup and detail response was fetched and run through the app's parsers (`test/api_parsing_test.dart`, which needs `API_FIXTURES` pointing at saved responses). All 11 parser tests pass.

## Not verified

- 18 Nov 2026 form-options and lookup changes: analyzer clean, unit tests pass, every lookup response checked live on staging; not yet run in the simulator.

- The Android APK is built and signed on GitHub Actions, but has not been run on a device or emulator.
- On the simulator: sample create / edit / delete, batch edit + delete, and contract edit + delete. The other forms were tested against the API with the app's exact request bodies.
- The offer, sale and ex-factory edit screens (7 Nov 2026), 10 parties and party edits, and new buyer / seller (9 Nov 2026) were tested against the API with the app's exact request bodies, not yet in the simulator.
- Buyer and seller create were tested on the server and the TEST records deleted.
- The dashboard-driven Home and split sale totals (9 Nov 2026) were checked by parsing live responses with the app's models, not yet in the simulator.
- 17 Nov 2026 additions checked in the simulator (More, Users list/detail, tasting report, sample tasting section, bulk lots both tabs) and against live responses; no tasting, park, bulk or user change was saved from the app.
- 12 Nov 2026 rebuild: every tab, list, detail, form, dialog, calendar, switch and picker checked in the iOS simulator (light and dark). Android only through the CI build.

## API status

Re-checked against the staging server on 9 Nov 2026, signed in as admin, with marked TEST records that were deleted afterwards. All 22 issues found on 5 Nov are fixed. Details: `docs/API_DOCS.md` → Write tests and Re-tests.

### Working

| Area | Endpoints | Used in the app |
|---|---|---|
| Auth | `POST /auth/login`, `POST /auth/logout`, `GET /auth/me` | Sign in, sign out |
| Lookups | `GET /buyers`, `/sellers`, `/gardens` (search), `/grades`, `/negotiators`, `/posting-lists`, `/courier-entries/services` (services and addresses) | All pickers; buyers also feed offer parties |
| Buyers, sellers | `POST /buyers` (`buyer_name`), `DELETE /buyers/{id}`, `POST /sellers` (`seller_name`), `DELETE /sellers/{id}` | "Add as a new buyer / seller" in the pickers |
| Offer lists | list, detail, create (10 parties; duplicate → 409 with the existing offer; `duplicate_action` override / reoffer / reject), edit (packing date; parties: null clears, a missing key keeps), delete | ✅ |
| Offered today | `GET /samples-offered-today`, single and bulk buyer allocation | ✅ |
| Samples | list (arrival date and search filters), detail, create (duplicate → 422, resend with `is_duplicate`), edit (all fields), delete (422 when buyers are allocated) | ✅ |
| Batches | list, detail, create (keeps `batch_date`), auto-batch for a date, edit (`status`, `remarks`), delete | ✅ |
| Bid book | list, detail (404 once deleted), create, edit (full and status-only), delete | ✅ |
| Courier | list, detail, create (JSON or with photo, posting lists linked), buyer address prefill, edit, delete | ✅ |
| Contracts | list, detail, create, edit (items replaced; missing price → 422), delete | ✅ |
| Sales register | list (`sales_entries`), detail, create, edit (too many packages → 422 on `pkgs`), delete | ✅ |
| Ex-factory | list with metrics, detail, create (reconciles on save; matching sale → `matched`), edit, delete, CSV export | ✅ |
| Dashboard | `GET /dashboard/summary` (counts per module) | Home tiles, sales card and the sales / ex-factory checklist items |
| Errors | 401 on expired token, 404 for missing records and unknown paths, 405 as plain JSON, 409 duplicate offer, 422 with field errors | ✅ |

### Needs fixes from the API developer

The 10 client-feedback requests (12 Nov 2026) were all built by 17 Nov 2026 and are used by the app: sorting (`sort_by` / `sort_dir`), `garden_id` filter, posting lists by buyer, grades per garden, the arrival-date permission, users and roles, sample `for_company` / `sample_type` / `party_id` (+ `GET /billing-companies`), bulk bids, tasting (save, park/unpark, filters, `GET /reports/tasting`) and the new permissions. Still open:

1. `POST /bid-book/bulk` fails with a raw SQL error ("Column 'max_bid' cannot be null") when a lot has no max bid. Max bid should be optional, and SQL must never reach the response.
2. Tasting scale (answered 18 Nov): batch testing is 0–100 (the website flow); `POST /samples/{id}/tasting` stays a quick 0–10 score. The route that saves batch testing scores is still missing.
3. Sample 28 (SMP2026080002) was marked tasted by an accidental empty `POST /samples/28/tasting` on 17 Nov 2026 (`evaluated_at` / `evaluated_by` changed; scores were already there). Restore its previous evaluation fields from the server logs.
4. Not testable as super admin: that `POST`/`PUT /samples` refuses a non-today arrival date without `samples.edit_arrival_date`.
5. Fixed 18 Nov: `party` comes back as `{id, buyer_name, code}`.
6. Branches (20 Nov 2026). The website lists only the selected branch's records (Switch Branch), but the API saves app records with `branch_id = null`, so they appear in no branch on the website. The app's Home has a branch switch (`form-options` → `offices`) and already sends the choice as `branch_id` (body of every create, including form uploads such as courier photos and sample bulk upload, but not users, buyers or sellers; query of every list read) and an `X-Branch-Id` header. The API needs to:
   - save `branch_id` on create for every module (offer lists, samples, batches, bid book, courier, contracts, sales register, ex-factory), the same way the website saves the session branch;
   - filter list and dashboard reads by `branch_id` when it is sent, the same way the website filters by the selected branch (no `branch_id` = all branches);
   - set a branch on records already saved without one, e.g. offer list 5281.

   21 Nov 2026: the first two are done (checked on offer lists and samples: a create keeps `branch_id`, and lists filter by `branch_id` or `X-Branch-Id`). Still open: records saved without a branch show in no branch's list.
7. Offer tasting (21 Nov 2026): there is no offer route; the app marks offers with the marking sheet (`POST /samples/manual-marking`, rows `offer_list,<id>,1` under `item_type,item_ref,mark_for_tasting`). The server looks offers up within the sheet's `branch_id`, so the app sends each offer's own branch. Marking creates a sample from the offer (`related_sample`). `PUT /offer-lists/{id}` ignores `tasting_mark`, and marks made through the sheet get no `tasting_mark_updated_at`. A JSON route like `POST /samples/bulk-mark` for offers would be simpler.

## Not built yet (from the spec)

- Offline read cache (drift). Lists currently need a connection; the offline banner and write blocking are in place.
- Form drafts (autosave) and "Discard changes?" on back.
- Flavors (dev/staging/prod entry points), Sentry. (Android release CI is done: see the README.)
- Tests (unit, widget, golden, integration).
- Localisation files (`.arb`); strings are inline for now.
