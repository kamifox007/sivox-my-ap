-- 1. Update Events table for Location Tracking
ALTER TABLE events ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE events ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE events ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'DZ';

-- 2. Update Staff Assignments for Permissions
ALTER TABLE staff_assignments ADD COLUMN IF NOT EXISTS permissions JSONB DEFAULT '{"can_scan": true, "can_cancel": false, "can_manual_ticket": false}';

-- 2b. Update Bookings for Tracking and Auditing
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

-- 3. Create Staff Shifts table
CREATE TABLE IF NOT EXISTS staff_shifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    staff_id UUID REFERENCES auth.users(id),
    assignment_id UUID,
    start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    end_time TIMESTAMP WITH TIME ZONE,
    start_lat DOUBLE PRECISION,
    start_lng DOUBLE PRECISION,
    end_lat DOUBLE PRECISION,
    end_lng DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Create Staff Logs (Audit Trail)
CREATE TABLE IF NOT EXISTS staff_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id),
    user_name TEXT,
    role TEXT,
    action_type TEXT, -- e.g., 'ENTRY_SCAN', 'CANCEL_BOOKING', 'MANUAL_TICKET'
    description TEXT,
    related_event_id UUID REFERENCES events(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Enable RLS
ALTER TABLE staff_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Organizers can see logs for their events" ON staff_logs FOR SELECT USING (EXISTS (SELECT 1 FROM events e JOIN organizer_profiles op ON e.organizer_id = op.id WHERE e.id = staff_logs.related_event_id AND op.owner_id = auth.uid()));
CREATE POLICY "Staff can insert logs" ON staff_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
