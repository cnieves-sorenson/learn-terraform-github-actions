#!/bin/bash
  
# Variables passed as arguments
FIRST_NAME=$1
LAST_NAME=$2
DOB=$3

# Docker container details
CONTAINER_NAME="openemr"
MYSQL_USER="root"
MYSQL_PASSWORD="root"
MYSQL_DB="openemr"

# Get Docker container ID
CONTAINER_ID=$(sudo docker ps --filter "name=$CONTAINER_NAME" --format "{{.ID}}")

# Find the patient ID (pid)
PID=$(sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -sN -e \"SELECT pid FROM patient_data WHERE fname='$FIRST_NAME' AND lname='$LAST_NAME' AND DOB='$DOB';\"")

# Check if PID is found
if [ -z "$PID" ]; then
          echo "No patient found with the given details."
            exit 1
fi

# Find the maximum form_id and encounter
MAX_FORM_ID=$(sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -sN -e \"SELECT IFNULL(MAX(form_id), 0) FROM forms;\"")
MAX_ENCOUNTER=$(sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -sN -e \"SELECT IFNULL(MAX(encounter), 0) FROM form_encounter;\"")

# Increment form_id and encounter
FORM_ID=$((MAX_FORM_ID + 1))
ENCOUNTER=$((MAX_ENCOUNTER + 1))

# Insert into forms
sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -e \"
INSERT INTO forms (
    date, encounter, form_name, form_id, pid, user, groupname, authorized, formdir, therapy_group_id
) VALUES (
    NOW(), $ENCOUNTER, 'New Patient Encounter', $FORM_ID, $PID, 'admin', 'Default', 1, 'newpatient', NULL
);\""

# Insert into form_encounter
sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -e \"
INSERT INTO form_encounter (
    date, onset_date, reason, facility, pc_catid, facility_id, billing_facility, sensitivity, referral_source, pid, encounter,
        pos_code, class_code, external_id, parent_encounter_id, provider_id, discharge_disposition, referring_provider_id, 
            encounter_type_code, encounter_type_description, in_collection
    ) VALUES (
        NOW(), NOW(), '', 'Your Clinic Name Here', 5, 3, 3, 'normal', '', $PID, $ENCOUNTER, NULL, 'AMB', '', 1, 1, '', 0, '', '', 0
);\""

echo "Encounter inserted successfully for patient ID: $PID"

# Insert into procedure_order
sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -e \"
INSERT INTO procedure_order (
    provider_id,
    patient_id,
    encounter_id,
    date_collected,
    date_ordered,
    order_priority,
    order_status,
    patient_instructions,
    activity,
    control_id,
    lab_id,
    specimen_type,
    specimen_location,
    specimen_volume,
    date_transmitted,
    clinical_hx,
    external_id,
    order_diagnosis,
    billing_type,
    specimen_fasting,
    order_psc,
    order_abn,
    collector_id,
    account,
    account_facility,
    provider_number,
    procedure_order_type
) VALUES (
    1,  -- provider_id
    $PID,  -- patient_id
    (SELECT MAX(encounter) FROM form_encounter WHERE pid = $PID), -- encounter_id
    NOW(),  -- date_collected
    NOW(),  -- date_ordered
    '',  -- order_priority
    '',  -- order_status
    '',  -- patient_instructions
    1,  -- activity
    '',  -- control_id
    1,  -- lab_id
    '',  -- specimen_type
    '',  -- specimen_location
    '',  -- specimen_volume
    NULL,  -- date_transmitted
    '',  -- clinical_hx
    NULL,  -- external_id
    'ICD10:Z00.00',  -- order_diagnosis
    '',  -- billing_type
    '',  -- specimen_fasting
    0,  -- order_psc
    'not_required',  -- order_abn
    0,  -- collector_id
    '',  -- account
    '0',  -- account_facility
    NULL,  -- provider_number
    'procedure'  -- procedure_order_type
);
INSERT INTO procedure_order_code (
    procedure_order_id,
    procedure_order_seq,
    procedure_code,
    procedure_name,
    procedure_source,
    diagnoses,
    do_not_send,
    procedure_order_title,
    procedure_type,
    transport,
    date_end,
    reason_code,
    reason_description,
    reason_date_low,
    reason_date_high,
    reason_status
) VALUES (
    (SELECT MAX(procedure_order_id) from procedure_order),
    1,
    '0',
    'baseline',
    '1',
    '',
    0,
    'procedure',
    'procedure',
    '',
    NULL,
    '',
    NULL,
    NULL,
    NULL,
    NULL
);
INSERT INTO forms (
    date,                -- Current date and time
    encounter,           -- Encounter must match encounter thats being placed for given patient. 
    form_name,           -- 'baseline-procedure'
    form_id,             -- form id has to match procedure_order id? 
    pid,                 -- Patient ID 1
    user,                -- 'admin'
    groupname,           -- 'Default'
    authorized,          -- Authorized status 1 (true)
    formdir,             -- 'procedure_order'
    therapy_group_id,    -- Therapy group ID NULL
    issue_id,            -- Issue ID 0
    provider_id          -- Provider ID 0
) 
VALUES (
    NOW(),               -- Current date and time
    (SELECT MAX(encounter) FROM form_encounter WHERE pid = $PID),  -- Max encounter 
    'baseline-procedure',-- Form name
    (SELECT MAX(procedure_order_id) FROM procedure_order), -- Form ID
    $PID,                -- Patient ID
    'admin',             -- User
    'Default',           -- Group name
    1,                   -- Authorized status
    'procedure_order',   -- Form directory
    NULL,                -- Therapy group ID
    0,                   -- Issue ID
    0                    -- Provider ID
);\""

echo "procedure_order inserted successfully for patient ID: $PID"