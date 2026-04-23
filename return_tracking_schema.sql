-- ============================================
-- RETURN TRACKING SYSTEM - DATABASE SCHEMA
-- Additional tables for eBay Returns Tracking Workflow
-- ============================================

-- ============================================
-- TABLE: returns
-- Master table for tracking return lifecycle
-- ============================================
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

COMMENT ON TABLE returns IS 'Master table for tracking return lifecycle';
COMMENT ON COLUMN returns.marketplace IS 'Sales platform (e.g., eBay)';
COMMENT ON COLUMN returns.return_id IS 'eBay return ID';
COMMENT ON COLUMN returns.order_number IS 'Original order number';
COMMENT ON COLUMN returns.internal_order_id IS 'Reference to internal unit';
COMMENT ON COLUMN returns.status_current IS 'Current status of the return';
COMMENT ON COLUMN returns.final_outcome IS 'Final outcome of the return';
COMMENT ON COLUMN returns.internal_bucket IS 'Internal classification bucket';
COMMENT ON COLUMN returns.classifier_source IS 'Source of classification';
COMMENT ON COLUMN returns.classifier_confidence IS 'Confidence level of classification';

-- Create indexes for returns table
CREATE INDEX idx_returns_return_id ON returns(return_id);
CREATE INDEX idx_returns_order_number ON returns(order_number);
CREATE INDEX idx_returns_sku ON returns(sku);
CREATE INDEX idx_returns_internal_order_id ON returns(internal_order_id);
CREATE INDEX idx_returns_status_current ON returns(status_current);
CREATE INDEX idx_returns_final_outcome ON returns(final_outcome);
CREATE INDEX idx_returns_created_at ON returns(created_at);

-- ============================================
-- TABLE: return_events
-- Audit trail for return-related events
-- ============================================
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

COMMENT ON TABLE return_events IS 'Audit trail for return-related events';
COMMENT ON COLUMN return_events.source_type IS 'Source of the event: email, page_scrape, manual';
COMMENT ON COLUMN return_events.email_message_id IS 'Gmail message ID for tracking';
COMMENT ON COLUMN return_events.raw_payload IS 'Raw email payload for reference';
COMMENT ON COLUMN return_events.parsed_data IS 'Parsed data from email';

-- Create indexes for return_events table
CREATE INDEX idx_return_events_return_id ON return_events(return_id);
CREATE INDEX idx_return_events_email_message_id ON return_events(email_message_id);
CREATE INDEX idx_return_events_event_type ON return_events(event_type);
CREATE INDEX idx_return_events_created_at ON return_events(created_at);

-- ============================================
-- TABLE: email_processing_log
-- Track processed emails to avoid duplicate processing
-- ============================================
CREATE TABLE email_processing_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email_message_id VARCHAR(200) UNIQUE NOT NULL, -- Gmail's unique message ID
    email_subject TEXT,
    email_sender VARCHAR(200),
    received_date TIMESTAMP,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_status VARCHAR(50) DEFAULT 'success', -- success, failed, skipped
    processing_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE email_processing_log IS 'Track processed emails to avoid duplicate processing';
COMMENT ON COLUMN email_processing_log.email_message_id IS 'Gmail unique message ID';
COMMENT ON COLUMN email_processing_log.processing_status IS 'Result of email processing';
COMMENT ON COLUMN email_processing_log.processing_notes IS 'Additional notes about processing';

-- Create indexes for email_processing_log table
CREATE INDEX idx_email_processing_log_message_id ON email_processing_log(email_message_id);
CREATE INDEX idx_email_processing_log_processed_at ON email_processing_log(processed_at);
CREATE INDEX idx_email_processing_log_status ON email_processing_log(processing_status);

-- ============================================
-- TRIGGER: Update timestamps for returns table
-- ============================================
CREATE TRIGGER update_returns_updated_at BEFORE UPDATE ON returns FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VIEWS: Return-related queries
-- ============================================

-- View: Return summary with key metrics
CREATE OR REPLACE VIEW vw_returns_summary AS
SELECT 
    r.id AS return_id,
    r.return_id AS ebay_return_id,
    r.order_number,
    r.buyer_username,
    r.item_title,
    r.brand,
    r.sku,
    r.return_reason_ebay,
    r.status_current,
    r.final_outcome,
    r.internal_bucket,
    r.recommended_fix,
    r.opened_at,
    r.closed_at,
    EXTRACT(EPOCH FROM (r.closed_at - r.opened_at))/86400 AS days_to_close
FROM returns r;

COMMENT ON VIEW vw_returns_summary IS 'Summary view of return information with key metrics';

-- View: Return statistics by brand
CREATE OR REPLACE VIEW vw_returns_by_brand AS
SELECT 
    r.brand,
    COUNT(*) AS total_returns,
    COUNT(CASE WHEN r.final_outcome = 'refunded_after_return_received' THEN 1 END) AS refunded_after_return_received,
    COUNT(CASE WHEN r.final_outcome = 'refunded_without_return_received' THEN 1 END) AS refunded_without_return_received,
    COUNT(CASE WHEN r.final_outcome = 'closed_buyer_never_shipped' THEN 1 END) AS closed_buyer_never_shipped,
    COUNT(CASE WHEN r.final_outcome = 'closed_other' THEN 1 END) AS closed_other,
    ROUND(COUNT(CASE WHEN r.final_outcome = 'closed_buyer_never_shipped' THEN 1 END) * 100.0 / COUNT(*), 2) AS percent_closed_buyer_never_shipped
FROM returns r
WHERE r.brand IS NOT NULL
GROUP BY r.brand
ORDER BY total_returns DESC;

COMMENT ON VIEW vw_returns_by_brand IS 'Return statistics grouped by brand';

-- View: Return classification summary
CREATE OR REPLACE VIEW vw_returns_classification AS
SELECT 
    r.internal_bucket,
    COUNT(*) AS count,
    COUNT(CASE WHEN r.final_outcome = 'closed_buyer_never_shipped' THEN 1 END) AS buyer_never_shipped_count,
    ROUND(COUNT(CASE WHEN r.final_outcome = 'closed_buyer_never_shipped' THEN 1 END) * 100.0 / COUNT(*), 2) AS buyer_never_shipped_percent
FROM returns r
WHERE r.internal_bucket IS NOT NULL
GROUP BY r.internal_bucket
ORDER BY count DESC;

COMMENT ON VIEW vw_returns_classification IS 'Return classification summary with buyer never shipped stats';

-- ============================================
-- END OF RETURN TRACKING SCHEMA
-- ============================================