
drop table if exists Catalogs;
drop table if exists Filters;
drop table if exists Products;
drop table if exists ProductCatalogs;
drop table if exists Registration;
drop table if exists MachineData;
drop table if exists Targets;
drop table if exists Clients;

drop table if exists Subscriptions;
drop table if exists ClientSubscriptions;

drop table if exists RepositoryContentData;


-- integer id for "Clients" for faster joins compared to GUID with CHAR(50)
--    GUID remains primary key until all code that deals with GUIDs gets adapted
--    all new tables refering to a Client should use Clients.ID from now on
create table Clients(ID          INT UNSIGNED AUTO_INCREMENT UNIQUE KEY,
                     GUID        CHAR(50) PRIMARY KEY,
                     HOSTNAME    VARCHAR(100) DEFAULT '',
                     TARGET      VARCHAR(100),
                     DESCRIPTION VARCHAR(500) DEFAULT '',
                     LASTCONTACT TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                     NAMESPACE   VARCHAR(300) NOT NULL DEFAULT '',
                     SECRET      CHAR(50) NOT NULL DEFAULT ''
                    );


create table Subscriptions(SUBID          CHAR(50) PRIMARY KEY, 
                           REGCODE        VARCHAR(100),
                           SUBNAME        VARCHAR(100) NOT NULL,
                           SUBTYPE        CHAR(20)  DEFAULT "UNKNOWN",
                           SUBSTATUS      CHAR(20)  DEFAULT "UNKNOWN",
                           SUBSTARTDATE   TIMESTAMP NULL default NULL,
                           SUBENDDATE     TIMESTAMP NULL default CURRENT_TIMESTAMP,
                           SUBDURATION    BIGINT    DEFAULT 0,
                           SERVERCLASS    CHAR(50),
                           PRODUCT_CLASS  VARCHAR(100),
                           NODECOUNT      integer NOT NULL,
                           CONSUMED       integer DEFAULT 0,
                           CONSUMEDVIRT   integer DEFAULT 0,
                           INDEX idx_sub_product_class (PRODUCT_CLASS)
                          );

create table ClientSubscriptions(GUID    CHAR(50) NOT NULL,
                                 SUBID   CHAR(50) NOT NULL,
                                 PRIMARY KEY(GUID, SUBID)
                                );

create table Registration(GUID         CHAR(50) NOT NULL,
                          PRODUCTID    integer NOT NULL,
                          REGDATE      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                          NCCREGDATE   TIMESTAMP NULL default NULL,
                          NCCREGERROR  integer DEFAULT 0,
                          PRIMARY KEY(GUID, PRODUCTID)
                       -- FOREIGN KEY (ProductID) REFERENCES Products  -- FOREIGN KEY not supported by sqlite3
                         );

--
-- MachineData.TYPE is one of
--   0 -  data that gets synced to NCC
--   1 -  patchstatus information
--   2 -  reserved for JobQueue usage
--   3... <free>
create table MachineData(GUID          CHAR(50) NOT NULL,
                         KEYNAME       CHAR(50) NOT NULL,
                         VALUE         BLOB,
                         TYPE          INTEGER UNSIGNED NOT NULL default 0,
                         PRIMARY KEY(GUID, KEYNAME)
                      -- FOREIGN KEY (GUID) REFERENCES Registration (GUID) ON DELETE CASCADE -- FOREIGN KEY not supported by sqlite3
                        );

-- used for NU catalogs and single RPMMD sources
create table Catalogs(ID          INT AUTO_INCREMENT UNIQUE KEY,
                      CATALOGID   CHAR(50) PRIMARY KEY,
                      NAME        VARCHAR(200) NOT NULL, 
                      DESCRIPTION VARCHAR(500), 
                      TARGET      VARCHAR(100),           -- null in case of single RPMMD source
                      LOCALPATH   VARCHAR(300) NOT NULL,
                      EXTHOST     VARCHAR(300) NOT NULL,  
                      EXTURL      VARCHAR(300) NOT NULL,  -- where to mirror from
                      CATALOGTYPE CHAR(10) NOT NULL,
                      DOMIRROR    CHAR(1) DEFAULT 'N',
                      MIRRORABLE  CHAR(1) DEFAULT 'N',
                      SRC         CHAR(1) DEFAULT 'N',    -- N NCC    C Custom
                      STAGING     CHAR(1) DEFAULT 'N',    -- N No  Y Yes
                      LAST_MIRROR TIMESTAMP NULL DEFAULT NULL,
                      UNIQUE(NAME, TARGET)
                     );

-- Package filters
--
-- One record represents a filter element. Filter elements referencing the same
-- CATALOG_ID make up the whole filter.
--
-- TYPE is one of
--   1 name exact
--   2 name regex
--   3 name-version exact (covers also patch ID)
--   4 patch security level (patch only)
--
create table Filters(ID            INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                     CATALOG_ID    INT NOT NULL,
                     TYPE          INT NOT NULL DEFAULT 1,
                     VALUE         VARCHAR(255),
                     UNIQUE KEY (CATALOG_ID, TYPE, VALUE)
                     -- FOREIGN KEY (CATALOG_ID) REFERENCES Catalogs(ID) ON DELETE CASCADE
                     -- FOREIGN KEY (SUBCATALOG_ID) REFERENCES Subcatalogs(ID) ON DELETE CASCADE
                    );


-- copy of NNW_PRODUCT_DATA
create table Products (
                PRODUCTDATAID   integer NOT NULL PRIMARY KEY,
                PRODUCT         VARCHAR(500) NOT NULL,
                VERSION         VARCHAR(100),
                REL             VARCHAR(100),
                ARCH            VARCHAR(100),
                PRODUCTLOWER    VARCHAR(500) NOT NULL,
                VERSIONLOWER    VARCHAR(100),
                RELLOWER        VARCHAR(100),
                ARCHLOWER       VARCHAR(100),
                FRIENDLY        VARCHAR(700),
                PARAMLIST       TEXT,
                NEEDINFO        TEXT,
                SERVICE         TEXT,
                PRODUCT_LIST    CHAR(1),
                PRODUCT_CLASS   CHAR(50),
                SRC         CHAR(1) DEFAULT 'N',    -- N NCC   C Custom
                UNIQUE(PRODUCTLOWER, VERSIONLOWER, RELLOWER, ARCHLOWER),
                INDEX idx_prod_product_class (PRODUCT_CLASS)  
                );


create table ProductCatalogs(PRODUCTDATAID integer NOT NULL,
                             CATALOGID     CHAR(50) NOT NULL,
                             OPTIONAL      CHAR(1) DEFAULT 'N',
                             SRC         CHAR(1) DEFAULT 'N',    -- N NCC   C Custom
                             PRIMARY KEY(PRODUCTDATAID, CATALOGID)
                            );

create table Targets (OS      VARCHAR(200) NOT NULL PRIMARY KEY,
                      TARGET  VARCHAR(100) NOT NULL,
                      SRC         CHAR(1) DEFAULT 'N'    -- N NCC   C Custom
                     );

create table RepositoryContentData(localpath   VARCHAR(300) PRIMARY KEY,
                                   name        VARCHAR(300) NOT NULL,
                                   checksum    CHAR(50)     NOT NULL,
                                   INDEX idx_repo_cont_data_name_checksum (name, checksum)
                                  );
-- end

--
-- JobQueue 
-- 
-- TYPE is one of  (also refer to documentation)
--      0  -  unknown/undefined
--      1  -  patchstatus
--      2  -  sw_push
--      3  -  update
--      4  -  execute
--      5  -  reboot
--      6  -  configure 
--      7  -  wait

create table JobQueue ( ID          INTEGER UNSIGNED NOT NULL,
                        GUID_ID     INTEGER UNSIGNED NOT NULL,
                        PARENT_ID   INTEGER UNSIGNED NULL default NULL,
                        NAME        CHAR NOT NULL default '',
                        DESCRIPTION MEDIUMTEXT,
                        TYPE        INTEGER UNSIGNED NOT NULL default 0,
                        ARGUMENTS   BLOB,
                        RESULTS     BLOB,
                        STATUS      TINYINT UNSIGNED NOT NULL default 0,
                        STATUSTEXT  TEXT,
                        REQUESTED   TIMESTAMP default CURRENT_TIMESTAMP,
                        TARGETED    TIMESTAMP NULL default NULL,
                        EXPIRES     TIMESTAMP NULL default NULL,
                        FINISHED    TIMESTAMP NULL default NULL,
                        PERSISTENT  TINYINT(1) NOT NULL default 0,
                        TIMELAG     TIME NULL default NULL,
                        PRIMARY KEY (ID, GUID_ID)
                      );
