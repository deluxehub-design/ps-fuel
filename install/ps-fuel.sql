CREATE TABLE IF NOT EXISTS `ps_fuel_vehicles` (
  `plate` varchar(16) NOT NULL,
  `fuel` decimal(6,2) NOT NULL DEFAULT 100.00,
  `leak_level` tinyint unsigned NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`plate`),
  KEY `idx_ps_fuel_vehicles_updated` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_stations` (
  `station_id` varchar(64) NOT NULL,
  `label` varchar(100) NOT NULL,
  `owner_citizenid` varchar(64) DEFAULT NULL,
  `owner_name` varchar(100) DEFAULT NULL,
  `balance` bigint NOT NULL DEFAULT 0,
  `price_multiplier` decimal(4,2) NOT NULL DEFAULT 1.00,
  `total_sales` bigint NOT NULL DEFAULT 0,
  `total_litres` decimal(12,2) NOT NULL DEFAULT 0.00,
  `stock` decimal(12,2) NOT NULL DEFAULT 10000.00,
  `capacity` decimal(12,2) NOT NULL DEFAULT 10000.00,
  PRIMARY KEY (`station_id`),
  KEY `idx_ps_fuel_stations_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `station_id` varchar(64) NOT NULL,
  `citizenid` varchar(64) DEFAULT NULL,
  `player_name` varchar(100) DEFAULT NULL,
  `amount_paid` int NOT NULL DEFAULT 0,
  `fuel_amount` decimal(8,2) NOT NULL DEFAULT 0.00,
  `transaction_type` varchar(32) NOT NULL DEFAULT 'fuel',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_station_created` (`station_id`,`created_at`),
  KEY `idx_ps_fuel_transactions_citizen` (`citizenid`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_settings` (
  `setting_key` varchar(64) NOT NULL,
  `setting_value` varchar(255) NOT NULL,
  PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_profiles` (
  `model_hash` bigint NOT NULL,
  `model_name` varchar(80) NOT NULL,
  `fuel_type` varchar(16) NOT NULL DEFAULT 'petrol',
  `fast_charge_enabled` tinyint(1) NOT NULL DEFAULT 0,
  `updated_by` varchar(64) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`model_hash`),
  KEY `idx_ps_fuel_vehicle_type` (`fuel_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_audit_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `action` varchar(64) NOT NULL,
  `source` int NOT NULL DEFAULT 0,
  `citizenid` varchar(64) DEFAULT NULL,
  `details` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_ps_fuel_audit_action_created` (`action`,`created_at`),
  KEY `idx_ps_fuel_audit_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `ps_fuel_settings` (`setting_key`, `setting_value`)
VALUES ('market_multiplier', '1.0')
ON DUPLICATE KEY UPDATE `setting_key` = `setting_key`;

ALTER TABLE `ps_fuel_vehicles`
  ADD COLUMN IF NOT EXISTS `leak_level` tinyint unsigned NOT NULL DEFAULT 0;

ALTER TABLE `ps_fuel_stations`
  ADD COLUMN IF NOT EXISTS `stock` decimal(12,2) NOT NULL DEFAULT 10000.00,
  ADD COLUMN IF NOT EXISTS `capacity` decimal(12,2) NOT NULL DEFAULT 10000.00;


-- Standalone/vMenu framework wallet. Only used when PS Fuel is not running
-- Qbox, QBCore, ESX, or a custom framework adapter.
CREATE TABLE IF NOT EXISTS `ps_fuel_wallets` (
    `identifier` varchar(128) NOT NULL,
    `cash` bigint NOT NULL DEFAULT 0,
    `bank` bigint NOT NULL DEFAULT 0,
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PS Fuel 3.4.0 advanced systems

CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_energy` (
        `plate` varchar(16) NOT NULL,
        `model_hash` bigint NOT NULL DEFAULT 0,
        `capacity` decimal(10,2) NOT NULL DEFAULT 60.00,
        `fuel_family` varchar(16) NOT NULL DEFAULT 'petrol',
        `last_fuel_type` varchar(24) DEFAULT NULL,
        `recommended_octane` smallint NOT NULL DEFAULT 87,
        `mixture_json` longtext DEFAULT NULL,
        `contamination` decimal(6,3) NOT NULL DEFAULT 0.000,
        `filter_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `pump_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `injector_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `tank_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `charging_port_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `ev_battery_health` decimal(6,2) NOT NULL DEFAULT 100.00,
        `odometer_km` decimal(12,2) NOT NULL DEFAULT 0.00,
        `lifetime_fuel` decimal(14,3) NOT NULL DEFAULT 0.000,
        `lifetime_cost` bigint NOT NULL DEFAULT 0,
        `trip_distance_km` decimal(12,3) NOT NULL DEFAULT 0.000,
        `trip_fuel` decimal(12,3) NOT NULL DEFAULT 0.000,
        `trip_cost` bigint NOT NULL DEFAULT 0,
        `trip_idle_fuel` decimal(12,3) NOT NULL DEFAULT 0.000,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`plate`), KEY `idx_psfuel_energy_model` (`model_hash`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_history` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `plate` varchar(16) NOT NULL,
        `station_id` varchar(64) DEFAULT NULL,
        `fuel_type` varchar(24) NOT NULL,
        `volume` decimal(10,3) NOT NULL DEFAULT 0,
        `amount_paid` int NOT NULL DEFAULT 0,
        `odometer_km` decimal(12,2) DEFAULT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`id`), KEY `idx_psfuel_history_plate` (`plate`,`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_fleet_accounts` (
        `account_id` varchar(64) NOT NULL,
        `label` varchar(100) NOT NULL,
        `job_name` varchar(64) DEFAULT NULL,
        `balance` bigint NOT NULL DEFAULT 0,
        `daily_limit` int NOT NULL DEFAULT 2500,
        `active` tinyint(1) NOT NULL DEFAULT 1,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_fleet_cards` (
        `card_id` varchar(64) NOT NULL,
        `account_id` varchar(64) NOT NULL,
        `holder_identifier` varchar(64) DEFAULT NULL,
        `holder_name` varchar(100) DEFAULT NULL,
        `pin_hash` varchar(128) DEFAULT NULL,
        `daily_limit` int NOT NULL DEFAULT 0,
        `spent_today` int NOT NULL DEFAULT 0,
        `spent_date` date DEFAULT NULL,
        `allowed_fuels` longtext DEFAULT NULL,
        `allowed_stations` longtext DEFAULT NULL,
        `active` tinyint(1) NOT NULL DEFAULT 1,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`card_id`), KEY `idx_psfuel_card_account` (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_loyalty` (
        `identifier` varchar(64) NOT NULL,
        `points` bigint NOT NULL DEFAULT 0,
        `lifetime_spend` bigint NOT NULL DEFAULT 0,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_station_employees` (
        `station_id` varchar(64) NOT NULL,
        `identifier` varchar(64) NOT NULL,
        `name` varchar(100) DEFAULT NULL,
        `role` varchar(32) NOT NULL DEFAULT 'employee',
        `permissions` longtext DEFAULT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`station_id`,`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_station_advanced` (
        `station_id` varchar(64) NOT NULL,
        `supplier_id` varchar(64) DEFAULT 'localfuel',
        `maintenance` decimal(6,2) NOT NULL DEFAULT 100.00,
        `storage_level` tinyint unsigned NOT NULL DEFAULT 0,
        `pump_level` tinyint unsigned NOT NULL DEFAULT 0,
        `charger_level` tinyint unsigned NOT NULL DEFAULT 0,
        `security_level` tinyint unsigned NOT NULL DEFAULT 0,
        `tanker_level` tinyint unsigned NOT NULL DEFAULT 0,
        `delivery_costs` bigint NOT NULL DEFAULT 0,
        `robbery_losses` bigint NOT NULL DEFAULT 0,
        `ev_revenue` bigint NOT NULL DEFAULT 0,
        PRIMARY KEY (`station_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_tanker_cargo` (
        `plate` varchar(16) NOT NULL,
        `fuel_type` varchar(24) NOT NULL DEFAULT 'diesel',
        `amount` decimal(12,2) NOT NULL DEFAULT 0,
        `capacity` decimal(12,2) NOT NULL DEFAULT 30000,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_private_points` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `owner_identifier` varchar(64) DEFAULT NULL,
        `station_id` varchar(64) DEFAULT NULL,
        `point_type` varchar(24) NOT NULL,
        `label` varchar(100) NOT NULL,
        `coords_json` longtext NOT NULL,
        `auth_json` longtext DEFAULT NULL,
        `active` tinyint(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ps_fuel_spills` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `station_id` varchar(64) DEFAULT NULL,
        `coords_json` longtext NOT NULL,
        `severity` decimal(5,2) NOT NULL DEFAULT 1.00,
        `expires_at` datetime NOT NULL,
        PRIMARY KEY (`id`), KEY `idx_psfuel_spill_expiry` (`expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `ps_fuel_settings` (`setting_key`,`setting_value`) VALUES ('wholesale_multiplier','1.0');

ALTER TABLE `ps_fuel_station_advanced` ADD COLUMN IF NOT EXISTS `promotion_per_litre` decimal(8,3) NOT NULL DEFAULT 0.000;

CREATE TABLE IF NOT EXISTS `ps_fuel_fleet_card_transactions` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `card_id` varchar(64) NOT NULL,
        `account_id` varchar(64) NOT NULL,
        `station_id` varchar(64) DEFAULT NULL,
        `fuel_type` varchar(24) DEFAULT NULL,
        `amount` int NOT NULL DEFAULT 0,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`id`), KEY `idx_psfuel_fleet_tx_card` (`card_id`,`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
