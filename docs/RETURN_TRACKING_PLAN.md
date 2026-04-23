# eBay Returns Tracking Workflow Implementation Plan

## Project Goal
Build a lightweight return lifecycle system inside our existing software. The system should search a Gmail label once per day, process all eBay return-related emails in that label, create or update one master return record per return, classify the return into our internal buckets, match the return to the correct eBay order and brand, and report return metrics including how many returns close because the buyer never ships the item back.

## Phase 1 Implementation Steps

### 1. Database Schema Extension
- Add `returns` table with all required columns as specified in requirements
- Add `return_events` table to store email/event audit trail
- Create appropriate indexes for performance
- Update existing schema with new tables

### 2. Email Parser Enhancement
- Extend `email_parser_service.py` to handle eBay return-related emails
- Add parsers for different return email types:
  - Return started / return approved
  - Buyer shipped the item back
  - Item delivered back to seller
  - Refund issued / refund sent
  - Return closed because buyer did not ship back in time
- Implement extraction of key fields: return_id, order number, buyer username, item title, etc.

### 3. Gmail Integration
- Update `gmail_service.py` to handle return email processing
- Implement daily polling mechanism for designated Gmail label
- Add email processing tracking to avoid duplicate processing
- Store raw email payload for audit trail

### 4. Return Matching Logic
- Create logic to match returns to internal orders using order number
- Enrich returns with SKU and brand information
- Implement deduplication by return_id

### 5. Classification Engine
- Implement return classification into internal buckets:
  - Size Issue/Fit
  - Condition Mismatch
  - Sizing Mismatch
  - Wrong Item
  - Shipping Damage
  - Low Intent Buyer
  - Needs Review
- Map classifications to recommended fixes

### 6. Status and Outcome Mapping
- Implement status mapping based on email signals:
  - Signal found → status_current → final_outcome
  - Return started/approved → opened or awaiting_buyer_shipment → still_open
  - Buyer shipped back → buyer_shipped → still_open
  - Item delivered back → delivered_back → still_open
  - Refund issued after delivery → refunded → refunded_after_return_received
  - Refund issued without delivery → refunded → refunded_without_return_received
  - Explicit no-shipment closure → closed_no_buyer_shipment → closed_buyer_never_shipped
  - Other explicit close → closed_other → closed_other

### 7. API Endpoints
- Add new endpoints in `app.py`:
  - GET `/api/returns` - List all returns with filtering
  - GET `/api/returns/<return_id>` - Get return details
  - POST `/api/returns/process-emails` - Process return emails from Gmail
  - GET `/api/returns/reports` - Get return metrics and reporting

### 8. Scheduler Integration
- Update `scheduler.py` to include daily return email processing job
- Configure timing for daily Gmail polling

### 9. Reporting Dashboard
- Create reporting functionality for required metrics:
  - Total returns opened
  - Total refunded
  - Total closed because buyer never shipped back
  - Percent of returns closed because buyer never shipped back
  - Count by internal bucket
  - Brand table: sold count, return count, return rate
  - Matched vs unmatched returns

## Technical Implementation Details

### Database Changes (`schema.sql`)
```sql
-- Add returns table
CREATE TABLE returns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    marketplace VARCHAR(50) DEFAULT 'eBay',
    return_id VARCHAR(100),
    order_number VARCHAR(100),
    buyer_username VARCHAR(200),
    item_title TEXT,
    brand VARCHAR(200),
    sku VARCHAR(100),
    internal_order_id UUID REFERENCES units(id),
    return_reason_ebay VARCHAR(200),
    buyer_comment TEXT,
    request_amount DECIMAL(10, 2),
    opened_at TIMESTAMP,
    buyer_ship_by_date TIMESTAMP,
    buyer_shipped_at TIMESTAMP,
    tracking_number VARCHAR(200),
    item_delivered_back_at TIMESTAMP,
    refund_issued_at TIMESTAMP,
    closed_at TIMESTAMP,
    status_current VARCHAR(50),
    final_outcome VARCHAR(50),
    internal_bucket VARCHAR(50),
    notes TEXT,
    recommended_fix TEXT,
    classifier_source VARCHAR(50),
    classifier_confidence DECIMAL(5, 4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add return_events table
CREATE TABLE return_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    return_id UUID REFERENCES returns(id) ON DELETE CASCADE,
    event_type VARCHAR(100),
    event_timestamp TIMESTAMP,
    source_type VARCHAR(50) DEFAULT 'email', -- email, page_scrape, manual
    email_message_id VARCHAR(200),
    email_subject TEXT,
    raw_payload TEXT,
    parsed_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_returns_return_id ON returns(return_id);
CREATE INDEX idx_returns_order_number ON returns(order_number);
CREATE INDEX idx_returns_sku ON returns(sku);
CREATE INDEX idx_return_events_return_id ON return_events(return_id);
CREATE INDEX idx_return_events_email_message_id ON return_events(email_message_id);
```

### New Python Classes (`database.py`)
```python
class Return(db.Model):
    __tablename__ = 'returns'
    
    id = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    marketplace = db.Column(db.String(50), default='eBay')
    return_id = db.Column(db.String(100))
    order_number = db.Column(db.String(100))
    buyer_username = db.Column(db.String(200))
    item_title = db.Column(db.Text)
    brand = db.Column(db.String(200))
    sku = db.Column(db.String(100))
    internal_order_id = db.Column(UUID(as_uuid=True), db.ForeignKey('units.id'))
    return_reason_ebay = db.Column(db.String(200))
    buyer_comment = db.Column(db.Text)
    request_amount = db.Column(db.Numeric(10, 2))
    opened_at = db.Column(db.DateTime)
    buyer_ship_by_date = db.Column(db.DateTime)
    buyer_shipped_at = db.Column(db.DateTime)
    tracking_number = db.Column(db.String(200))
    item_delivered_back_at = db.Column(db.DateTime)
    refund_issued_at = db.Column(db.DateTime)
    closed_at = db.Column(db.DateTime)
    status_current = db.Column(db.String(50))
    final_outcome = db.Column(db.String(50))
    internal_bucket = db.Column(db.String(50))
    notes = db.Column(db.Text)
    recommended_fix = db.Column(db.Text)
    classifier_source = db.Column(db.String(50))
    classifier_confidence = db.Column(db.Numeric(5, 4))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class ReturnEvent(db.Model):
    __tablename__ = 'return_events'
    
    id = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    return_id = db.Column(UUID(as_uuid=True), db.ForeignKey('returns.id'), nullable=False)
    event_type = db.Column(db.String(100))
    event_timestamp = db.Column(db.DateTime)
    source_type = db.Column(db.String(50), default='email')  # email, page_scrape, manual
    email_message_id = db.Column(db.String(200))
    email_subject = db.Column(db.Text)
    raw_payload = db.Column(db.Text)
    parsed_data = db.Column(JSONB)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
```

### Processing Logic
- Implement core rule: one return = one evolving record
- Avoid duplicate work by checking existing fields before updating
- Only page-scrape when needed for missing fields
- Store exact source of closure signals for no-shipment closures

## Testing Approach
1. Set up sample email folder with return email trigger samples
2. Validate parsing against sample emails before live processing
3. Test deduplication logic thoroughly
4. Verify status mapping works correctly
5. Confirm reporting metrics are accurate

## Build Order
1. **First Milestone**: Parse sample emails, create returns tables, show one evolving return record working end to end
2. **Second Milestone**: Order match, brand enrichment, and status tracking
3. **Third Milestone**: Classification, recommended fixes, and reporting

## Acceptance Criteria
- [ ] Daily job searches Gmail label without reprocessing already handled emails
- [ ] One return_id creates one master return record, not duplicates
- [ ] Later emails update the same return cleanly
- [ ] Buyer-shipped-back emails correctly move return into buyer_shipped status
- [ ] Explicit no-shipment closure emails/pages are counted correctly as closed_buyer_never_shipped
- [ ] Matched returns populate brand and contribute to brand return-rate reporting
- [ ] Dashboard shows summary counts, bucket counts, brand return rates, and no-shipment closure counts

## Timeline Estimate
- **Week 1**: Database schema and model implementation
- **Week 2**: Email parser enhancement and Gmail integration
- **Week 3**: Matching logic and classification engine
- **Week 4**: API endpoints and reporting
- **Week 5**: Integration, testing, and refinement

## Risk Mitigation
- Start with sample email folder before processing live emails
- Implement comprehensive logging for debugging
- Create backup strategy for return data
- Thoroughly test deduplication logic