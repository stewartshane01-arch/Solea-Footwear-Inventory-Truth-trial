1

2

3

4

eBay Returns Tracking Workflow
Instructions (V1)
Purpose: ingest return emails, match them to orders, classify them, and report brand return rates and buyer-no-ship closures.
1. Project goal
Build a lightweight return lifecycle system inside our existing software. The system should search a Gmail label once
per day, process all eBay return-related emails in that label, create or update one master return record per return,
classify the return into our internal buckets, match the return to the correct eBay order and brand, and report return
metrics including how many returns close because the buyer never ships the item back.
2. Scope for V1
Poll Gmail once per day, not continuously.
Use a Gmail label for all eBay return-related emails. Gmail should move the relevant emails into that label first.
The software should search only that label and process emails found there.
Treat each return as one master record that can be updated over time by later emails.
Use the buyer-shipped-back email as the main trigger for updating the return after it has been opened.
Use only explicit closure detection for buyer-no-ship closures. Do not infer closure from deadlines in V1.
Avoid duplicate work. If a field is already known and stored for the return, do not re-save it unless the newer source
clearly updates the value.
For V1, track brand return rate, reason buckets, recommended fixes, and count of returns that close because the
buyer never shipped the item back.
3. Inputs and sources
Source
Use
Notes
Gmail label
Primary event source
All relevant eBay return emails should be auto-labeled by Gmail before the software runs.
Sample Email folder holds return email trigger samples
Parser testing
Use this first so parsing can be validated safely before running on live labeled mail.
eBay return page
Secondary enrichment source
Use only when needed to fetch fields not already known from email or stored record.
Internal order data
Order match and brand enrichment
Use order number match first. Pull SKU and brand from internal system.
4. Core rule: one return = one evolving record
Do not treat each email as a separate return. Multiple emails may relate to the same return. Use return_id as the
primary unique key whenever available. All later emails should update the same return record.
5. Gmail workflow
Create a Gmail label such as EBAY_RETURNS_TRACKING.
Set Gmail filters/rules so all relevant eBay return emails are moved or labeled there.
The software runs once per day and searches that label only.
For each email in the label that has not already been processed, store the raw email payload and parse the useful
fields.
Mark the email as processed in the software database so the same email is not processed twice on the next daily
run.
6. Email types to recognize
Return started / return approved
Buyer shipped the item back
Item delivered back to seller
Refund issued / refund sent
Return closed because buyer did not ship back in time
The buyer-shipped-back email is an important trigger in this project. When that email appears, the software should
update the return status to reflect that the buyer has shipped the item back.
7. Database objects
7.1 returns
id
marketplace
return_id
order_number
buyer_username
item_title
brand
sku
internal_order_id
return_reason_ebay
buyer_comment
request_amount
opened_at
buyer_ship_by_date
buyer_shipped_at
tracking_number
item_delivered_back_at
refund_issued_at
closed_at
status_current
final_outcome
internal_bucket
notes
recommended_fix
classifier_source
classifier_confidence
created_at
updated_at
7.2 return_events
id
return_id
event_type
event_timestamp
source_type (email, page_scrape, manual)
email_message_id
email_subject
raw_payload
parsed_data
created_at
Every email or page update should create a return_events row. The returns table is the latest summary state; the
return_events table is the audit trail.
8. Processing logic
Search the Gmail label once per day.
Read all unprocessed emails in the label.
Parse the email and extract: return_id, order number, buyer username, item title, eBay return reason, request
amount, dates, and return page link.
If return_id already exists in returns, update that row. If not, create a new row.
Insert a return_events row for the email event.
Match the return to the internal order using order number first. Once matched, enrich the return with SKU and brand.
Classify the return into the internal bucket list and store the recommended fix.
If the email already provides all needed information for the event, do not open the eBay page. Only use the eBay
page when a needed field is missing.
If the eBay page is used, extract only fields still missing or fields that may have materially changed since the prior
stored version.
Update status_current and final_outcome according to the explicit event found.
9. Status and outcome mapping
Signal found
status_current
final_outcome
Return started / approved email or page
opened or awaiting_buyer_shipment
still_open
Buyer shipped item back email
buyer_shipped
still_open
Tracking present and confirmed in an update
buyer_shipped
still_open
Delivered back to seller email/page
delivered_back
still_open
Refund issued email/page after delivered-back event
refunded
refunded_after_return_received
Refund issued with no delivered-back event
refunded
refunded_without_return_received
Explicit email/page says buyer did not ship in time and return closed
closed_no_buyer_shipment
closed_buyer_never_shipped
Other explicit close state
closed_other
closed_other
10. Explicit no-shipment closure logic
Use method one only. Count a return as buyer-never-shipped only when an explicit signal exists in email or on the
eBay page. Do not infer this from missed deadlines in V1.
If the email or page explicitly says the buyer did not ship the item back in time, closed automatically, or that no refund
is required because the buyer did not send the item, set final_outcome = closed_buyer_never_shipped.
Store the exact source of the closure signal in the relevant return_events row.
Expose this count in reporting as a separate metric.
11. Avoiding duplicate work
If a field is already present in returns and a new source does not provide a better value, keep the existing value.
Only page-scrape when a field is missing or when the event suggests a real status change.
Deduplicate by return_id for returns and by email_message_id or return_id + event_type + event_timestamp for
return_events.
Do not create duplicate return rows because multiple emails arrived for the same return.
12. Internal classification buckets
Size Issue/Fit
Condition Mismatch
Sizing Mismatch
Wrong Item
Shipping Damage
Low Intent Buyer
Needs Review
Suggested rule order:
Use eBay return reason as the starting signal.
Use buyer comment if available to refine or override.
Apply simple keyword rules.
If unclear, set Needs Review.
13. Recommended fix mapping
Bucket
Recommended fix
Size Issue/Fit
Add fit note, width guidance, or brand-specific sizing note.
Sizing Mismatch
Audit size mapping and make size conversion clearer in listings.
Condition Mismatch
Improve defect photo coverage and listing condition review.
Wrong Item
Audit pick/pack verification and SKU scan checks.
Shipping Damage
Improve packaging standard.
Low Intent Buyer
Review offer policy and buyer-behavior patterns.
Needs Review
Manual review required before assigning fix.
14. Reporting required in V1
Total returns opened
Total refunded
Total closed because buyer never shipped back
Percent of returns closed because buyer never shipped back
Count by internal bucket
Brand table: sold count, return count, return rate
Matched vs unmatched returns
Brand return rate for V1 can be calculated as matched returns for the brand divided by sold orders for the brand over
the selected date range.
15. Build order
Set up Gmail label flow and parser against Sample Email folder.
Build returns and return_events tables.
Build daily label polling and processed-email tracking.
Build create/update logic for one master return per return_id.
Build order-number matching and brand enrichment.
Build explicit status/outcome mapping, including buyer-shipped and buyer-never-shipped closures.
Build classification rules and recommended fixes.
Add eBay page enrichment only for missing or changed fields.
Build simple dashboard/reporting for summary, buckets, brands, and no-shipment closures.
16. Acceptance criteria
The daily job searches the Gmail label and does not reprocess already handled emails.
One return_id creates one master return record, not duplicates.
Later emails update the same return cleanly.
Buyer-shipped-back emails correctly move the return into buyer_shipped status.
Explicit no-shipment closure emails/pages are counted correctly as closed_buyer_never_shipped.
Matched returns populate brand and contribute to brand return-rate reporting.
The dashboard shows summary counts, bucket counts, brand return rates, and no-shipment closure counts.
17. Recommendation on how to manage the build
First milestone should be: parse sample emails, create returns tables, and show one evolving return record working
end to end. Second milestone should be: order match, brand enrichment, and status tracking. Third milestone should
be: classification, recommended fixes, and reporting.