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