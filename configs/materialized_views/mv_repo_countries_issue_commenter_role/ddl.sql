CREATE TABLE IF NOT EXISTS `mv_repo_countries_issue_commenter_role`
(
    `repo_id` INT(11),
    `country_code` INT(11),
    `first_seen_at` DATE NOT NULL,
    PRIMARY KEY (`repo_id`, `country_code`),
    KEY idx_mrc_icr_on_repo_id_first_seen_at(`repo_id`, `first_seen_at`)
);
