-- Initialization script for Liferay DXP
-- MySQL 8.4 compatible (IDENTIFIED BY removed from GRANT syntax)

CREATE DATABASE IF NOT EXISTS lportal
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- MySQL 8.4: use ALTER USER instead of GRANT ... IDENTIFIED BY
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

SELECT SCHEMA_NAME AS 'Database',
       DEFAULT_CHARACTER_SET_NAME AS 'Charset',
       DEFAULT_COLLATION_NAME AS 'Collation'
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = 'lportal';
