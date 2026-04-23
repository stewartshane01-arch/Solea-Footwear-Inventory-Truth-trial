# eBay Returns Tracking System - Implementation Plan

## Overview
This document outlines the complete implementation plan for the eBay Returns Tracking feature, which will monitor Gmail for return-related emails, process them, match to internal orders, classify returns, and provide reporting on return metrics including buyer-no-ship closures.

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Database Schema](#database-schema)
3. [Implementation Phases](#implementation-phases)
4. [File Structure](#file-structure)
5. [Service Components](#service-components)
6. [API Endpoints](#api-endpoints)
7. [Scheduler Integration](#scheduler-integration)
8. [Testing Strategy](#testing-strategy)
9. [Deployment Checklist](#deployment-checklist)

---

## Architecture Overview

### System Flow
```
Gmail Label → Daily Scheduler → Email Parser → Return Processor → Database
                                                      ↓
                                            Order Matcher & Classifier
                                                      ↓
                                            eBay Page Enrichment (if needed)
                                                      ↓
                                            Dashboard & Reporting
```

### Key Principles
- **One return = one master record**: Multiple emails update the same return
- **Explicit detection only**: No deadline inference in V1
- **Avoid duplicate work**: Only fetch missing fields
- **Daily polling**: Process once per day, not continuously

---

## Database Schema

### Tables (Already Created)
✅ **returns** - Master return lifecycle table
✅ **return_events** - Audit trail for all return events
✅ **email_processing_log** - Track processed emails to prevent duplicates

### Key Relationships
- `returns.internal_order_id` → `units.id` (FK)
- `return_events.return_id` → `returns.id` (FK, CASCADE)

---

## Implementation Phases

### Phase 1: Gmail Integration & Email Processing
**Goal**: Set up Gmail label polling and email deduplication

#### Tasks:
1. **Create Gmail Label Management**
   - File: `gmail_service.py` (extend existing)
   - Add method: `get_emails_from_label(label_name, max_results=100)`
   - Add method: `search_label_by_name(label_name)`
   
2. **Create Email Processing Log Service**
   - File: `email_processing_service.py` (new)
   - Check if email already processed
   - Log processing status (success/failed/skipped)
   - Prevent duplicate processing

3. **Test with Sample Emails**
   - Create folder: `sample_emails/returns/`
   - Add sample return emails for testing
   - Test parser without live Gmail

**Deliverables**:
- Gmail can read from specific label
- Email deduplication works
- Processing log tracks all emails

---

### Phase 2: Return Email Parser
**Goal**: Parse eBay return emails to extract key fields

#### Tasks:
1. **Create eBay Return Email Parser**
   - File: `ebay_return_parser.py` (new)
   - Class: `EbayReturnParser`
   - Parse return_id, order_number, buyer_username, item_title
   - Parse return_reason_ebay, buyer_comment, request_amount
   - Parse dates: opened_at, buyer_ship_by_date, buyer_shipped_at
   - Parse tracking_number, item_delivered_back_at, refund_issued_at
   - Detect event type (return_opened, buyer_shipped, delivered, refunded, closed_no_ship)

2. **Email Type Detection**
   - Identify: Return started/approved
   - Identify: Buyer shipped item back
   - Identify: Item delivered back
   - Identify: Refund issued
   - Identify: Return closed (buyer never shipped)

3. **Test Parser with Samples**
   - Test all email types
   - Validate field extraction
   - Handle missing fields gracefully

**Deliverables**:
- Parser extracts all required fields
- Correctly identifies email types
- Returns structured data dict

---

### Phase 3: Return Processing Service
**Goal**: Create/update return records and handle return lifecycle

#### Tasks:
1. **Create Return Service**
   - File: `return_service.py` (new)
   - Class: `ReturnService`
   - Method: `process_return_email(parsed_email_data)`
   - Method: `create_or_update_return(return_data)`
   - Method: `create_return_event(return_id, event_data)`
   - Method: `match_to_internal_order(order_number)`

2. **Return Lifecycle Logic**
   - Check if return_id exists → update existing
   - If new → create new return record
   - Always create return_event entry
   - Update status_current based on event type
   - Update final_outcome based on explicit signals

3. **Order Matching**
   - Match by order_number to units table
   - Enrich with SKU and brand from matched unit
   - Handle unmatched returns gracefully

**Deliverables**:
- Returns are created/updated correctly
- Return events logged for audit trail
- Order matching works

---

### Phase 4: Status & Outcome Mapping
**Goal**: Implement status tracking and outcome classification

#### Tasks:
1. **Status Mapping Logic**
   - File: `return_service.py` (extend)
   - Map email signals to status_current:
     - `opened` / `awaiting_buyer_shipment`
     - `buyer_shipped`
     - `delivered_back`
     - `refunded`
     - `closed_no_buyer_shipment`
     - `closed_other`

2. **Outcome Mapping Logic**
   - Map to final_outcome:
     - `still_open`
     - `refunded_after_return_received`
     - `refunded_without_return_received`
     - `closed_buyer_never_shipped`
     - `closed_other`

3. **Explicit Closure Detection**
   - Only count buyer-never-shipped when explicit signal exists
   - Store closure source in return_events
   - No deadline inference in V1

**Deliverables**:
- Status transitions work correctly
- Outcomes mapped accurately
- Explicit closure detection implemented

---

### Phase 5: Return Classification
**Goal**: Classify returns into internal buckets and assign recommended fixes

#### Tasks:
1. **Create Classifier Service**
   - File: `return_classifier.py` (new)
   - Class: `ReturnClassifier`
   - Method: `classify_return(return_reason_ebay, buyer_comment)`
   - Method: `get_recommended_fix(internal_bucket)`

2. **Classification Rules**
   - Buckets:
     - Size Issue/Fit
     - Condition Mismatch
     - Sizing Mismatch
     - Wrong Item
     - Shipping Damage
     - Low Intent Buyer
     - Needs Review
   - Use eBay reason + buyer comment
   - Apply keyword matching
   - Default to "Needs Review" if unclear

3. **Recommended Fix Mapping**
   - Size Issue/Fit → Add fit note, width guidance
   - Sizing Mismatch → Audit size mapping
   - Condition Mismatch → Improve defect photos
   - Wrong Item → Audit pick/pack verification
   - Shipping Damage → Improve packaging
   - Low Intent Buyer → Review offer policy
   - Needs Review → Manual review required

**Deliverables**:
- Returns classified into buckets
- Recommended fixes assigned
- Classification logic documented

---

### Phase 6: eBay Page Enrichment (Optional)
**Goal**: Fetch missing fields from eBay return page when needed

#### Tasks:
1. **Create eBay Return Page Scraper**
   - File: `ebay_return_scraper.py` (new)
   - Class: `EbayReturnScraper`
   - Method: `fetch_return_details(return_id)`
   - Only fetch fields not already in database
   - Use Selenium or eBay API if available

2. **Conditional Enrichment**
   - Only scrape when critical field is missing
   - Don't re-fetch known fields
   - Log page scrape as return_event

**Deliverables**:
- Page scraper fetches missing fields
- Enrichment only when needed
- Scraping logged in return_events

---

### Phase 7: Scheduler Integration
**Goal**: Run daily return email processing automatically

#### Tasks:
1. **Add Return Check Job to Scheduler**
   - File: `scheduler.py` (extend existing)
   - Function: `check_return_emails()`
   - Poll Gmail label once per day
   - Process all unprocessed emails
   - Log results

2. **Scheduler Configuration**
   - Add to `.env`:
     ```
     RETURN_CHECK_INTERVAL_HOURS=24
     EBAY_RETURNS_GMAIL_LABEL=EBAY_RETURNS_TRACKING
     ```
   - Add job to `sync_scheduler.start_return_monitoring()`

3. **Error Handling**
   - Catch and log all errors
   - Continue processing other emails if one fails
   - Alert on critical failures

**Deliverables**:
- Daily scheduler runs automatically
- Processes all emails in label
- Errors logged and handled

---

### Phase 8: API Endpoints
**Goal**: Expose return data via REST API

#### Tasks:
1. **Create Return Endpoints**
   - File: `app.py` (extend existing)
   - `GET /api/returns` - List all returns with filters
   - `GET /api/returns/<return_id>` - Get return details
   - `GET /api/returns/stats` - Return statistics
   - `GET /api/returns/by-brand` - Returns grouped by brand
   - `GET /api/returns/by-bucket` - Returns grouped by classification

2. **Query Filters**
   - Filter by: status_current, final_outcome, internal_bucket
   - Filter by: brand, date range
   - Filter by: matched vs unmatched

3. **Response Format**
   - Return summary data
   - Include related events
   - Include matched unit info

**Deliverables**:
- All endpoints functional
- Filters work correctly
- Returns proper JSON responses

---

### Phase 9: Reporting & Dashboard
**Goal**: Provide return metrics and insights

#### Tasks:
1. **Create Return Metrics Endpoint**
   - File: `app.py` (extend)
   - `GET /api/returns/metrics`
   - Return:
     - Total returns opened
     - Total refunded
     - Total closed (buyer never shipped)
     - Percent closed (buyer never shipped)
     - Count by internal bucket
     - Brand return rates

2. **Brand Return Rate Calculation**
   - Query: matched returns by brand
   - Query: sold orders by brand (from units table)
   - Calculate: return_rate = returns / sold_orders
   - Support date range filtering

3. **Dashboard Views (SQL Views)**
   - Use existing views in schema:
     - `vw_returns_summary`
     - `vw_returns_by_brand`
     - `vw_returns_classification`

**Deliverables**:
- Metrics endpoint returns all required data
- Brand return rates calculated correctly
- Dashboard-ready data format

---

### Phase 10: Testing & Validation
**Goal**: Ensure system works end-to-end

#### Tasks:
1. **Unit Tests**
   - Test email parser with sample emails
   - Test classifier with various inputs
   - Test order matching logic
   - Test status/outcome mapping

2. **Integration Tests**
   - Test full flow: email → database
   - Test duplicate email handling
   - Test return updates (multiple emails for same return)
   - Test scheduler execution

3. **Manual Testing**
   - Process sample emails folder
   - Verify database records
   - Check API responses
   - Validate metrics calculations

**Deliverables**:
- All tests passing
- Sample data processed correctly
- System validated end-to-end

---

## File Structure

```
project_root/
├── docs/
│   ├── RETURN_TRACKING_PLAN.md (this file)
│   └── RETURN_TRACKING_IMPLEMENTATION_PLAN.md
├── sample_emails/
│   └── returns/
│       ├── return_opened.html
│       ├── buyer_shipped.html
│       ├── delivered_back.html
│       ├── refund_issued.html
│       └── closed_no_ship.html
├── ebay_return_parser.py (new)
├── return_service.py (new)
├── return_classifier.py (new)
├── email_processing_service.py (new)
├── ebay_return_scraper.py (new, optional)
├── gmail_service.py (extend)
├── scheduler.py (extend)
├── app.py (extend)
├── database.py (already has Return models)
└── return_tracking_schema.sql (already created)
```

---

## Service Components

### 1. EbayReturnParser
**Purpose**: Parse eBay return emails to extract structured data

**Methods**:
- `parse(email_data)` → dict
- `_extract_return_id(body)` → str
- `_extract_order_number(body)` → str
- `_extract_buyer_info(body)` → dict
- `_extract_dates(body)` → dict
- `_detect_event_type(subject, body)` → str

### 2. ReturnService
**Purpose**: Manage return lifecycle and database operations

**Methods**:
- `process_return_email(parsed_data)` → dict
- `create_or_update_return(return_data)` → Return
- `create_return_event(return_id, event_data)` → ReturnEvent
- `match_to_internal_order(order_number)` → Unit
- `enrich_from_ebay_page(return_id)` → dict

### 3. ReturnClassifier
**Purpose**: Classify returns and assign recommended fixes

**Methods**:
- `classify_return(return_reason, buyer_comment)` → str
- `get_recommended_fix(bucket)` → str
- `_match_keywords(text, keywords)` → bool

### 4. EmailProcessingService
**Purpose**: Track processed emails and prevent duplicates

**Methods**:
- `is_email_processed(message_id)` → bool
- `mark_email_processed(message_id, status, notes)` → EmailProcessingLog
- `get_unprocessed_emails(label_name)` → list

---

## API Endpoints

### Return Endpoints

#### GET /api/returns
List all returns with optional filters

**Query Parameters**:
- `status` - Filter by status_current
- `outcome` - Filter by final_outcome
- `bucket` - Filter by internal_bucket
- `brand` - Filter by brand
- `start_date` - Filter by opened_at >= date
- `end_date` - Filter by opened_at <= date
- `matched` - Filter by matched (true/false)

**Response**:
```json
{
  "returns": [
    {
      "id": "uuid",
      "return_id": "5123456789",
      "order_number": "27-13930-98148",
      "buyer_username": "buyer123",
      "item_title": "Nike Air Max...",
      "brand": "Nike",
      "sku": "00042150",
      "status_current": "buyer_shipped",
      "final_outcome": "still_open",
      "internal_bucket": "Size Issue/Fit",
      "opened_at": "2025-04-20T10:00:00Z",
      "request_amount": 51.00
    }
  ],
  "total": 25,
  "matched": 20,
  "unmatched": 5
}
```

#### GET /api/returns/:id
Get return details with events

**Response**:
```json
{
  "return": {
    "id": "uuid",
    "return_id": "5123456789",
    "order_number": "27-13930-98148",
    "buyer_username": "buyer123",
    "item_title": "Nike Air Max...",
    "brand": "Nike",
    "sku": "00042150",
    "internal_order_id": "uuid",
    "return_reason_ebay": "Doesn't fit",
    "buyer_comment": "Too small",
    "request_amount": 51.00,
    "opened_at": "2025-04-20T10:00:00Z",
    "buyer_ship_by_date": "2025-04-27T10:00:00Z",
    "buyer_shipped_at": "2025-04-22T14:30:00Z",
    "tracking_number": "1Z999AA10123456784",
    "status_current": "buyer_shipped",
    "final_outcome": "still_open",
    "internal_bucket": "Size Issue/Fit",
    "recommended_fix": "Add fit note, width guidance",
    "classifier_source": "keyword_match",
    "classifier_confidence": 0.85
  },
  "events": [
    {
      "id": "uuid",
      "event_type": "return_opened",
      "event_timestamp": "2025-04-20T10:00:00Z",
      "source_type": "email",
      "email_subject": "Return request from buyer123"
    },
    {
      "id": "uuid",
      "event_type": "buyer_shipped",
      "event_timestamp": "2025-04-22T14:30:00Z",
      "source_type": "email",
      "email_subject": "Buyer shipped your return"
    }
  ],
  "matched_unit": {
    "id": "uuid",
    "unit_code": "00042150",
    "product": {
      "brand": "Nike",
      "model": "Air Max 90",
      "size": "10"
    },
    "sold_at": "2025-04-15T12:00:00Z",
    "sold_price": 51.00
  }
}
```

#### GET /api/returns/stats
Get return statistics

**Query Parameters**:
- `start_date` - Filter by date range
- `end_date` - Filter by date range

**Response**:
```json
{
  "summary": {
    "total_returns": 100,
    "total_refunded": 75,
    "total_closed_buyer_never_shipped": 15,
    "percent_closed_buyer_never_shipped": 15.0,
    "matched_returns": 85,
    "unmatched_returns": 15
  },
  "by_bucket": [
    {
      "bucket": "Size Issue/Fit",
      "count": 40,
      "percent": 40.0
    },
    {
      "bucket": "Condition Mismatch",
      "count": 25,
      "percent": 25.0
    }
  ],
  "by_outcome": [
    {
      "outcome": "refunded_after_return_received",
      "count": 60
    },
    {
      "outcome": "closed_buyer_never_shipped",
      "count": 15
    }
  ]
}
```

#### GET /api/returns/by-brand
Get returns grouped by brand

**Query Parameters**:
- `start_date` - Filter by date range
- `end_date` - Filter by date range

**Response**:
```json
{
  "brands": [
    {
      "brand": "Nike",
      "total_returns": 30,
      "total_sold": 200,
      "return_rate": 15.0,
      "refunded_after_return": 20,
      "refunded_without_return": 5,
      "closed_buyer_never_shipped": 3,
      "percent_closed_buyer_never_shipped": 10.0
    },
    {
      "brand": "Adidas",
      "total_returns": 20,
      "total_sold": 150,
      "return_rate": 13.3,
      "refunded_after_return": 15,
      "refunded_without_return": 3,
      "closed_buyer_never_shipped": 2,
      "percent_closed_buyer_never_shipped": 10.0
    }
  ]
}
```

---

## Scheduler Integration

### Environment Variables
Add to `.env`:
```bash
# Return Tracking Configuration
RETURN_CHECK_INTERVAL_HOURS=24
EBAY_RETURNS_GMAIL_LABEL=EBAY_RETURNS_TRACKING
RETURN_PROCESSING_ENABLED=true
```

### Scheduler Job
Add to `scheduler.py`:

```python
def check_return_emails():
    """
    Check Gmail label for return emails and process them
    Runs once per day
    """
    logger.info("Checking for return emails...")
    
    db = SessionLocal()
    
    try:
        gmail = GmailService()
        if not gmail.is_connected():
            logger.error("Gmail not connected")
            return
        
        label_name = os.getenv('EBAY_RETURNS_GMAIL_LABEL', 'EBAY_RETURNS_TRACKING')
        
        # Get emails from label
        emails = gmail.get_emails_from_label(label_name, max_results=100)
        
        if not emails:
            logger.info("No return emails found")
            return
        
        logger.info(f"Found {len(emails)} return emails")
        
        # Process each email
        parser = EbayReturnParser()
        return_service = ReturnService(db)
        email_processing = EmailProcessingService(db)
        
        processed = 0
        errors = 0
        
        for email in emails:
            message_id = email.get('message_id')
            
            # Skip if already processed
            if email_processing.is_email_processed(message_id):
                logger.debug(f"Email {message_id} already processed, skipping")
                continue
            
            try:
                # Parse email
                parsed = parser.parse(email)
                
                if not parsed:
                    email_processing.mark_email_processed(
                        message_id, 'failed', 'Failed to parse email'
                    )
                    errors += 1
                    continue
                
                # Process return
                result = return_service.process_return_email(parsed)
                
                if result.get('success'):
                    email_processing.mark_email_processed(
                        message_id, 'success', f"Return {result.get('return_id')} processed"
                    )
                    processed += 1
                else:
                    email_processing.mark_email_processed(
                        message_id, 'failed', result.get('error')
                    )
                    errors += 1
                
            except Exception as e:
                logger.error(f"Error processing email {message_id}: {e}")
                email_processing.mark_email_processed(
                    message_id, 'failed', str(e)
                )
                errors += 1
        
        logger.info(f"Return email check complete: {processed} processed, {errors} errors")
        
    except Exception as e:
        logger.error(f"Error in check_return_emails: {e}")
    
    finally:
        db.close()


# Add to SyncScheduler class
def start_return_monitoring(self):
    """Start return email monitoring"""
    
    interval_hours = int(os.getenv('RETURN_CHECK_INTERVAL_HOURS', '24'))
    
    self.scheduler.add_job(
        func=check_return_emails,
        trigger=IntervalTrigger(hours=interval_hours),
        id='return_check_job',
        name='Check Return Emails Job',
        replace_existing=True,
        max_instances=1
    )
    
    logger.info(f"Return monitoring started - checking every {interval_hours} hours")
```

---

## Testing Strategy

### 1. Unit Tests
Create `tests/test_return_tracking.py`:

```python
import unittest
from ebay_return_parser import EbayReturnParser
from return_classifier import ReturnClassifier

class TestReturnParser(unittest.TestCase):
    def test_parse_return_opened_email(self):
        # Test parsing return opened email
        pass
    
    def test_parse_buyer_shipped_email(self):
        # Test parsing buyer shipped email
        pass
    
    def test_parse_closed_no_ship_email(self):
        # Test parsing closed no ship email
        pass

class TestReturnClassifier(unittest.TestCase):
    def test_classify_size_issue(self):
        # Test size issue classification
        pass
    
    def test_classify_condition_mismatch(self):
        # Test condition mismatch classification
        pass
```

### 2. Integration Tests
- Test full email → database flow
- Test duplicate email handling
- Test return updates
- Test order matching

### 3. Manual Testing Checklist
- [ ] Gmail label created and configured
- [ ] Sample emails processed successfully
- [ ] Returns created in database
- [ ] Return events logged
- [ ] Order matching works
- [ ] Classification assigns correct buckets
- [ ] API endpoints return correct data
- [ ] Metrics calculations accurate
- [ ] Scheduler runs on schedule
- [ ] Error handling works

---

## Deployment Checklist

### Pre-Deployment
- [ ] Database schema applied (return_tracking_schema.sql)
- [ ] All new Python files created
- [ ] Dependencies installed (no new dependencies needed)
- [ ] Environment variables configured
- [ ] Gmail label created: `EBAY_RETURNS_TRACKING`
- [ ] Gmail filters set up to auto-label return emails
- [ ] Sample emails folder created for testing

### Deployment Steps
1. Apply database schema:
   ```bash
   psql -h <host> -U <user> -d <database> -f return_tracking_schema.sql
   ```

2. Update environment variables in `.env`:
   ```bash
   RETURN_CHECK_INTERVAL_HOURS=24
   EBAY_RETURNS_GMAIL_LABEL=EBAY_RETURNS_TRACKING
   RETURN_PROCESSING_ENABLED=true
   ```

3. Deploy new code files

4. Restart application

5. Start return monitoring scheduler:
   ```bash
   POST /api/scheduler/start-return-monitoring
   ```

### Post-Deployment
- [ ] Verify scheduler is running
- [ ] Check logs for errors
- [ ] Process test emails
- [ ] Verify database records
- [ ] Test API endpoints
- [ ] Monitor for 24 hours

---

## Acceptance Criteria

### Functional Requirements
✅ Daily job searches Gmail label and processes emails
✅ One return_id creates one master return record (no duplicates)
✅ Later emails update the same return cleanly
✅ Buyer-shipped-back emails correctly update status
✅ Explicit no-shipment closure emails counted correctly
✅ Matched returns populate brand and contribute to return rate
✅ Dashboard shows all required metrics

### Data Quality
✅ No duplicate return records
✅ No duplicate email processing
✅ All events logged in return_events
✅ Order matching accuracy > 90%
✅ Classification accuracy > 80%

### Performance
✅ Process 100 emails in < 5 minutes
✅ API response time < 500ms
✅ No memory leaks in scheduler

---

## Next Steps After V1

### V2 Enhancements
1. **Deadline Inference**: Infer buyer-no-ship from missed deadlines
2. **Real-time Processing**: Process emails as they arrive (not just daily)
3. **AI Classification**: Use Claude AI for better classification
4. **Automated Responses**: Auto-respond to certain return types
5. **Predictive Analytics**: Predict return likelihood at listing time
6. **Multi-platform Support**: Extend to Poshmark, Mercari returns

### V2 Features
- Return trend analysis
- Buyer return history tracking
- Automated return approval/denial
- Integration with shipping label generation
- Return cost tracking (shipping, restocking)

---

## Support & Maintenance

### Monitoring
- Check scheduler logs daily
- Monitor email processing success rate
- Track unmatched returns
- Review classification accuracy

### Troubleshooting
- **No emails processed**: Check Gmail label and filters
- **Duplicate returns**: Check return_id extraction logic
- **Order matching fails**: Verify order_number format
- **Classification incorrect**: Review keyword rules

### Documentation
- Keep sample emails updated
- Document new email patterns
- Update classification rules as needed
- Maintain API documentation

---

## Conclusion

This implementation plan provides a complete roadmap for building the eBay Returns Tracking system. Follow the phases sequentially, test thoroughly at each stage, and validate against the acceptance criteria before moving to production.

**Estimated Timeline**: 2-3 weeks for V1 implementation

**Key Success Metrics**:
- 100% of return emails processed
- < 5% duplicate records
- > 90% order matching accuracy
- > 80% classification accuracy
- 100% uptime for scheduler

---

**Document Version**: 1.0  
**Last Updated**: April 23, 2026  
**Author**: Implementation Team
