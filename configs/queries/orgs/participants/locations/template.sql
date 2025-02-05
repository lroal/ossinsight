WITH repos AS (
    SELECT
        gr.repo_id, gr.repo_name
    FROM github_repos gr
    WHERE
        gr.owner_id = {{ownerId}}
        {% if repoIds.size > 0 %}
        AND gr.repo_id IN ({{ repoIds | join: ',' }})
        {% endif %}
),
{% if excludeSeenBefore %}
countries_seen_before AS (
    SELECT
        country_code
    FROM
        {% case role %}
        {% when 'pr_creators' %} mv_repo_countries_pr_creator_role
        {% when 'pr_reviewers' %} mv_repo_countries_pr_reviewer_role
        {% when 'issue_creators' %} mv_repo_countries_issue_creator_role
        {% when 'commit_authors' %} mv_repo_countries_commit_author_role
        {% when 'pr_commenters' %} mv_repo_countries_issue_commenter_role
        {% when 'issue_commenters' %} mv_repo_countries_pr_commenter_role
        {% else %} mv_repo_countries_stargazer_role
        {% endcase %} b
    WHERE
        b.repo_id IN (SELECT repo_id FROM repos)
        {% case period %}
        {% when 'past_7_days' %} AND b.first_seen_at < (NOW() - INTERVAL 7 DAY)
        {% when 'past_28_days' %} AND b.first_seen_at < (NOW() - INTERVAL 28 DAY)
        {% when 'past_90_days' %} AND b.first_seen_at < (NOW() - INTERVAL 90 DAY)
        {% when 'past_12_months' %} AND b.first_seen_at < (NOW() - INTERVAL 12 MONTH)
        {% endcase %}
    GROUP BY country_code
),
{% endif %}
participants_per_country AS (
    SELECT
        gu.country_code,
        COUNT(DISTINCT actor_login) AS participants
    FROM github_events ge
    JOIN github_users gu ON ge.actor_login = gu.login
    WHERE
        ge.repo_id IN (SELECT repo_id FROM repos)
        {% case role %}
        {% when 'pr_creators' %}
        AND ge.type = 'PullRequestEvent' AND ge.action = 'opened'
        {% when 'pr_reviewers' %}
        AND ge.type = 'PullRequestReviewEvent' AND ge.action = 'created'
        {% when 'issue_creators' %}
        AND ge.type = 'IssuesEvent' AND ge.action = 'opened'
        {% when 'commit_authors' %}
        AND ge.type = 'PushEvent' AND ge.action = ''
        {% when 'pr_commenters' %}
        AND ge.type = 'IssueCommentEvent' AND ge.action = 'created'
        AND EXISTS (
            SELECT 1
            FROM mv_repo_pull_requests mrpr
            WHERE mrpr.repo_id = ge.repo_id AND mrpr.number = ge.number
        )
        {% when 'issue_commenters' %}
        AND ge.type = 'IssueCommentEvent' AND ge.action = 'created'
        AND EXISTS (
            SELECT 1
            FROM mv_repo_issues mri
            WHERE mri.repo_id = ge.repo_id AND mri.number = ge.number
        )
        {% else %}
        -- Events considered as participation (Exclude `WatchEvent`, which means star a repo).
        AND ge.type IN ('IssueCommentEvent',  'DeleteEvent',  'CommitCommentEvent',  'MemberEvent',  'PushEvent',  'PublicEvent',  'ForkEvent',  'ReleaseEvent',  'PullRequestReviewEvent',  'CreateEvent',  'GollumEvent',  'PullRequestEvent',  'IssuesEvent',  'PullRequestReviewCommentEvent')
        AND ge.action IN ('added', 'published', 'reopened', 'closed', 'created', 'opened', '')
        {% endcase %}
        {% if excludeBots %}
        -- Exclude bot users.
        AND LOWER(ge.actor_login) NOT LIKE '%bot%'
        AND ge.actor_login NOT IN (SELECT login FROM blacklist_users LIMIT 255)
        {% endif %}
        {% if excludeUnknown %}
        -- Exclude users with no country code.
        AND gu.country_code NOT IN ('', 'N/A', 'UND')
        {% endif %}
        {% case period %}
        {% when 'past_7_days' %} AND ge.created_at > (NOW() - INTERVAL 7 DAY)
        {% when 'past_28_days' %} AND ge.created_at > (NOW() - INTERVAL 28 DAY)
        {% when 'past_90_days' %} AND ge.created_at > (NOW() - INTERVAL 90 DAY)
        {% when 'past_12_months' %} AND ge.created_at > (NOW() - INTERVAL 12 MONTH)
        {% endcase %}
    GROUP BY gu.country_code
),
participants_total AS (
    SELECT SUM(participants) AS total FROM participants_per_country
)
SELECT
    ppc.country_code,
    ppc.participants,
    ROUND(ppc.participants / pt.total * 100, 2) AS percentage
FROM
    participants_per_country ppc,
    participants_total pt
{% if excludeSeenBefore %}
-- Exclude countries that have been seen before.
WHERE ppc.country_code NOT IN (SELECT country_code FROM countries_seen_before)
{% endif %}
ORDER BY ppc.participants DESC
LIMIT {{ n }}
