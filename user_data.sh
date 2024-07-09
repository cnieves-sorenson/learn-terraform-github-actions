#!/bin/sh 
echo "making tmp and script directory/files"
# Create log directory
mkdir -p /tmp

#create script directory
mkdir -p /scripts

#create scripting files
sudo touch /scripts/insert_procedure.sh
sudo chmod u+rwx /scripts/insert_procedure.sh 
sudo chown ubuntu:ubuntu /scripts/insert_procedure.sh

sudo touch /scripts/insert_result.sh
sudo chmod u+rwx /scripts/insert_result.sh 
sudo chown ubuntu:ubuntu /scripts/insert_result.sh

#----------------------------------------------------------------------------
#BEGINNING OF INSERT_PROCEDURE SCRIPT FILE

sudo tee /scripts/insert_procedure.sh > /dev/null << 'EOF'
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
    '0',  -- collector_id
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
EOF

#-----------------------------------------------------------------------------
#END OF INSERT_PROCEDURE SCRIPT FILE

#-----------------------------------------------------------------------------
#BEGINNING OF INSERT_RESULT SCRIPT FILE
sudo tee /scripts/insert_result.sh > /dev/null << 'EOF'
#!/bin/bash
  
# Variables passed as arguments
FIRST_NAME=$1
LAST_NAME=$2
DOB=$3
RESULT=$4
ABNORMAL=$5

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



sudo docker exec $CONTAINER_ID /bin/sh -c "
mysql -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB -e \"
SET @min_procedure_order_id = (
    SELECT MIN(procedure_order_id)
    FROM procedure_order
    WHERE patient_id = $PID
);
INSERT INTO procedure_report (
    procedure_order_id,           -- ID of the procedure order      
    procedure_order_seq,          -- Sequence number of the procedure order             
    date_collected,               -- Date the sample was collected              
    date_collected_tz,            -- Timezone of the collection date              
    date_report,                  -- Date the report was generated                 
    date_report_tz,               -- Timezone of the report date                 
    source,                       -- Source of the report                 
    specimen_num,                 -- Specimen number                 
    report_status,                -- Status of the report                 
    review_status,                -- Review status of the report                     
    report_notes                  -- Notes on the report                     
) VALUES (
    @min_procedure_order_id,      -- procedure_order_id      
    1,                            -- procedure_order_seq (default is 1)             
    NOW(),                        -- date_collected              
    '',                           -- date_collected_tz (empty string is acceptable)              
    NOW(),                        -- date_report                 
    '',                           -- date_report_tz (empty string is acceptable)                 
    0,                            -- source (default is 0)                 
    '',                           -- specimen_num (empty string is acceptable)                 
    'final',                      -- report_status                 
    'reviewed',                   -- review_status (default is 'received')                     
    'This is a dummy report note.' -- report_notes                     
);

SET @max_procedure_report_id = (
    SELECT MAX(procedure_report_id)
    FROM procedure_report
);
INSERT INTO procedure_result (
    procedure_report_id,
    result_data_type,
    result_code,
    result_text,
    date,
    facility,
    units,
    result,
    \\\`range\\\`,
    abnormal,
    comments,
    document_id,
    result_status,
    date_end
) VALUES (
    @max_procedure_report_id,
    'S',
    'S',
    'baseline',
    NOW(),
    '',
    '(units)',
    '$RESULT',
    '100',
    '$ABNORMAL',
    '',
    0,
    'final',
    NOW()                      
);
\""

echo "Result insertion successful for patient ID: $PID"
EOF


# Redirect all output to a log file in /tmp
exec > /tmp/user_data.log 2>&1

echo "User data script started"

echo "updating package lists"
sudo apt-get update

sleep 60
# is docker running?
echo "checking if docker is running"
if ! sudo systemctl is-active --quiet docker; then
    echo "Docker is not running!" 
    exit 1
fi

# get the container ID of the running OpenEMR container
echo "getting container id"
CONTAINER_ID=$(sudo docker ps --filter "name=openemr" --format "{{.ID}}")

# ensure the container ID is found
if [ -z "$CONTAINER_ID" ]; then
    echo "OpenEMR container not found!"
    exit 1
fi
echo "container id found, enabling api permissions"
              
# Configure OpenEMR for API Enable

sudo docker exec $CONTAINER_ID /bin/sh -c "mysql -u root -proot -e \"USE openemr; UPDATE globals SET gl_value = '1' WHERE gl_name IN ('rest_api', 'rest_fhir_api', 'rest_portal_api');\""
              
# Insert demo data into the db 
echo "inserting demo data into the database..."
sudo docker exec $CONTAINER_ID /bin/sh -c '
mysql -u root -proot -e "
USE openemr;

# insert address book baseline user
INSERT INTO users (
    uuid, username, password, authorized, fname, mname, lname, suffix, federaltaxid, federaldrugid, upin, facility, facility_id, see_auth, active, npi, title, specialty, billname, email, email_direct, google_signin_email, url, assistant, organization, valedictory, street, streetb, city, state, zip, street2, streetb2, city2, state2, zip2, phone, fax, phonew1, phonew2, phonecell, notes, cal_ui, taxonomy, calendar, abook_type, default_warehouse, irnpool, state_license_number, weno_prov_id, newcrop_user_role, cpoe, physician_type, main_menu_role, patient_menu_role, portal_user, supervisor_id, billing_facility, billing_facility_id 
) VALUES (
    UNHEX(\"727A353F4B7D3F3F3110DD91183F3F3F\"), \"\", \"\", 0, \"\", NULL, \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"\", \"baseline\", 0, 0, 1, \"baseline\", \"\", \"\", \"baseline\", \"baseline\", \"baseline\", NULL, \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"AR\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"AZ\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", \"baseline\", 1, \"baseline\", 0, \"ord_lab\", \"\", \"\", NULL, NULL, NULL, 0, NULL, \"standard\", \"standard\", 0, 0, NULL, 0
);
              
# Insert into procedure_providers
INSERT INTO procedure_providers (
    uuid, name, npi, send_app_id, send_fac_id, recv_app_id, recv_fac_id, DorP, direction, protocol, remote_host, login, password, orders_path, results_path, notes, lab_director, active, type
) VALUES (
    NULL, \"baseline\", \"\", \"\", \"\", \"\", \"\", \"D\", \"B\", \"DL\", \"\", \"\", \"\", \"\", \"\", \"\", 5, 1, NULL
);
              
# Insert procedure type
INSERT INTO procedure_type (
    procedure_type_id, parent, name, lab_id, procedure_code, procedure_type, body_site, specimen, route_admin, laterality, description, standard_code, related_code, units, \`range\`, seq, activity, notes, transport, procedure_type_name
) VALUES (
    1, 0, '\''baseline'\'', 1, '\''0'\'', '\''grp'\'', '\'''\'' ,'\'''\'' ,'\'''\'' ,'\'''\'' ,'\''baseline'\'', '\'''\'' ,'\'''\'' ,'\'''\'' ,'\'''\'' , 0, 1, '\'''\'' , NULL, '\''procedure'\''
), (
    2, 1, '\''baseline'\'', 1, '\''0'\'', '\''ord'\'', '\'''\'' ,'\'''\'' ,'\'''\'' ,'\'''\'' ,'\''baseline'\'', '\''0'\'', '\'''\'' ,'\'''\'' ,'\'''\'' , 0, 1, '\'''\'' , NULL, '\''procedure'\''
), (
    3, 2, '\''baseline'\'', 1, '\''0'\'', '\''res'\'', '\'''\'' ,'\'''\'' ,'\'''\'' ,'\'''\'' ,'\''baseline'\'', '\'''\'' ,'\'''\'' ,'\'''\'' ,'\'''\'' , 0, 1, '\'''\'' , NULL, '\''procedure'\''
);
              
# Insert patient_data for patients
INSERT INTO patient_data (
lname, fname, mname, DOB, sex, ss, drivers_license, status, genericname1, genericval1, pubpid, pid, email
) VALUES
(\"Doe\", \"John\", \"\", \"1970-01-01\", \"Male\", \"123-45-6789\", \"D1234567\", \"active\", \"preferred_language\", \"English\", \"12345\", 1, \"john.doe@example.com\"),
(\"Smith\", \"Jane\", \"A\", \"1980-05-15\", \"Female\", \"987-65-4321\", \"D8765432\", \"active\", \"preferred_language\", \"Spanish\", \"67890\", 2, \"jane.smith@example.com\"),
(\"Brown\", \"Robert\", \"B\", \"1990-03-22\", \"Male\", \"111-22-3333\", \"D1122334\", \"active\", \"preferred_language\", \"French\", \"54321\", 3, \"robert.brown@example.com\"),
(\"Johnson\", \"Emily\", \"C\", \"1975-08-30\", \"Female\", \"444-55-6666\", \"D4455667\", \"active\", \"preferred_language\", \"German\", \"98765\", 4, \"emily.johnson@example.com\"),
(\"Williams\", \"Michael\", \"D\", \"1965-11-12\", \"Male\", \"777-88-9999\", \"D7788990\", \"active\", \"preferred_language\", \"Chinese\", \"13579\", 5, \"michael.williams@example.com\"),
(\"Jones\", \"Sarah\", \"E\", \"2000-02-28\", \"Female\", \"222-33-4444\", \"D2233445\", \"active\", \"preferred_language\", \"Japanese\", \"24680\", 6, \"sarah.jones@example.com\"),
(\"Garcia\", \"David\", \"F\", \"1985-07-19\", \"Male\", \"555-66-7777\", \"D5566778\", \"active\", \"preferred_language\", \"Russian\", \"13579\", 7, \"david.garcia@example.com\"),
(\"Martinez\", \"Laura\", \"G\", \"1995-10-05\", \"Female\", \"888-99-0000\", \"D8899001\", \"active\", \"preferred_language\", \"Italian\", \"86420\", 8, \"laura.martinez@example.com\"),
(\"Davis\", \"James\", \"H\", \"1972-04-23\", \"Male\", \"123-45-6780\", \"D1234568\", \"active\", \"preferred_language\", \"Portuguese\", \"97531\", 9, \"james.davis@example.com\"),
(\"Rodriguez\", \"Patricia\", \"I\", \"1982-09-17\", \"Female\", \"321-54-9876\", \"D3215498\", \"active\", \"preferred_language\", \"Korean\", \"86420\", 10, \"patricia.rodriguez@example.com\");

"
'
              
echo "Configuration complete."
