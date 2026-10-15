CREATE UNIQUE INDEX ux_customers_active_email
    ON postal.customers USING btree (lower(email)) WHERE deleted_at IS NULL;

CREATE INDEX ix_shipments_active_status
    ON postal.shipments USING btree (status_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX ix_shipments_sender ON postal.shipments USING btree (sender_id);
CREATE INDEX ix_shipments_recipient ON postal.shipments USING btree (recipient_id);
CREATE INDEX ix_parcels_shipment ON postal.parcels USING btree (shipment_id);
CREATE INDEX ix_events_shipment_time
    ON postal.shipment_events USING btree (shipment_id, occurred_at, id);
CREATE INDEX ix_payments_shipment ON postal.payments USING btree (shipment_id);
CREATE INDEX ix_audit_entity_time
    ON postal.audit_log USING btree (entity_id, changed_at DESC);

CREATE INDEX ix_customers_search ON postal.customers USING gin
    (to_tsvector('simple', full_name || ' ' || email)) WHERE deleted_at IS NULL;
CREATE INDEX ix_audit_new_data ON postal.audit_log USING gin (new_data jsonb_path_ops);
