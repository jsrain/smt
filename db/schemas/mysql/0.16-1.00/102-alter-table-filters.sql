
alter table Filters add column STAGINGGROUP_ID INT NOT NULL DEFAULT 1;

DELIMITER $$

DROP PROCEDURE IF EXISTS smt.drop_index_if_exists $$
CREATE PROCEDURE smt.drop_index_if_exists(in theTable varchar(128), in theIndexName varchar(128) )
BEGIN
 IF((SELECT COUNT(*) AS index_exists
       FROM information_schema.statistics
      WHERE TABLE_SCHEMA = DATABASE()
        AND table_name = theTable
        AND index_name = theIndexName) > 0) THEN
   SET @s = CONCAT('DROP INDEX ' , theIndexName , ' ON ' , theTable);
   PREPARE stmt FROM @s;
   EXECUTE stmt;
 END IF;
END $$

DELIMITER ;

call smt.drop_index_if_exists('Filters', 'CATALOG_ID');

alter table Filters add unique key CATALOG_ID (CATALOG_ID, STAGINGGROUP_ID, TYPE, VALUE);

