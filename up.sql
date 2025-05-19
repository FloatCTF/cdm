DROP TABLE IF EXISTS
    users,
    teams,
    challenges_categories,
    challenges,
    challenges_attachments,
    challenge_instances,
    challenges_instances_flags,
    challenges_solves,
    challenges_submissions,
    notifications,
    logs
CASCADE;

CREATE TABLE users (
        id SERIAL PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        email TEXT UNIQUE NOT NULL,
        nickname TEXT NOT NULL,
        password TEXT NOT NULL,
        team_id INT,
        role TEXT NOT NULL CHECK (role IN ('user', 'admin', 'captain')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE teams (
        id SERIAL PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        score NUMERIC NOT NULL DEFAULT 0.0,
        is_banned BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE challenges_categories (
        id SERIAL PRIMARY KEY,
        name TEXT UNIQUE NOT NULL
);

CREATE TABLE challenges (
        id SERIAL PRIMARY KEY,
        challenge_path TEXT NOT NULL,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        author TEXT,
        category_id INT NOT NULL,
        points NUMERIC NOT NULL,
        is_dynamic_flag BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE challenges_attachments (
        id SERIAL PRIMARY KEY,
        challenge_id INT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE challenges_instances (
        id SERIAL PRIMARY KEY,
        challenge_id INT NOT NULL,
        content TEXT NOT NULL,
        user_id INT NOT NULL,
        team_id INT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'stopped', 'error')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        end_at TIMESTAMPTZ NOT NULL,
        destroy_at TIMESTAMPTZ,
        UNIQUE(team_id, challenge_id)
);

CREATE TABLE challenges_instances_flags (
        id SERIAL PRIMARY KEY,
        flag TEXT NOT NULL,
        challenge_instance_id INT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE challenges_solves (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        team_id INT NOT NULL,
        challenge_id INT NOT NULL,
        challenge_instance_id INT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE (user_id, challenge_id)
);

CREATE TABLE challenges_submissions (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        team_id INT NOT NULL,
        challenge_id INT NOT NULL,
        challenge_instance_id INT NOT NULL,
        flag TEXT NOT NULL,
        is_correct BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE logs (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        action_type TEXT NOT NULL CHECK (action_type IN ('start', 'destroy', 'submit', 'login', 'join_team', 'create_team')),
        detail TEXT NOT NULL,
        ip_address INET NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE VIEW scoreboard AS
SELECT
        t.id AS team_id,
        t.name AS team_name,
        SUM(c.points) AS total_score,
        MAX(cs.created_at) AS last_solve_time
FROM challenges_solves cs
JOIN teams t ON cs.team_id = t.id
JOIN challenges c ON cs.challenge_id = c.id
WHERE t.is_banned = FALSE
GROUP BY t.id
ORDER BY total_score DESC, last_solve_time ASC;

-- users.team_id → teams.id
ALTER TABLE users
    ADD CONSTRAINT fk_users_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL;

-- challenges.category_id → challenges_categories.id
ALTER TABLE challenges
    ADD CONSTRAINT fk_challenges_category FOREIGN KEY (category_id) REFERENCES challenges_categories(id) ON DELETE SET NULL;

-- challenges_attachments.challenge_id → challenges.id
ALTER TABLE challenges_attachments
    ADD CONSTRAINT fk_attachments_challenge FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE CASCADE;

-- challenges_instances.challenge_id → challenges.id
ALTER TABLE challenges_instances
    ADD CONSTRAINT fk_instances_challenge FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE CASCADE;

-- challenges_instances.user_id → users.id
ALTER TABLE challenges_instances
    ADD CONSTRAINT fk_instances_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- challenges_instances.team_id → teams.id
ALTER TABLE challenges_instances
    ADD CONSTRAINT fk_instances_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE;

-- challenges_instances_flags.challenge_instance_id → challenges_instances.id
ALTER TABLE challenges_instances_flags
    ADD CONSTRAINT fk_instance_flags FOREIGN KEY (challenge_instance_id) REFERENCES challenges_instances(id) ON DELETE CASCADE;

-- challenges_solves.user_id → users.id
ALTER TABLE challenges_solves
    ADD CONSTRAINT fk_solves_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- challenges_solves.team_id → teams.id
ALTER TABLE challenges_solves
    ADD CONSTRAINT fk_solves_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE;

-- challenges_solves.challenge_id → challenges.id
ALTER TABLE challenges_solves
    ADD CONSTRAINT fk_solves_challenge FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE CASCADE;

-- challenges_solves.challenge_instance_id → challenges_instances.id
ALTER TABLE challenges_solves
    ADD CONSTRAINT fk_solves_instance FOREIGN KEY (challenge_instance_id) REFERENCES challenges_instances(id) ON DELETE SET NULL;

-- challenges_submissions.user_id → users.id
ALTER TABLE challenges_submissions
    ADD CONSTRAINT fk_submissions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- challenges_submissions.team_id → teams.id
ALTER TABLE challenges_submissions
    ADD CONSTRAINT fk_submissions_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE;

-- challenges_submissions.challenge_id → challenges.id
ALTER TABLE challenges_submissions
    ADD CONSTRAINT fk_submissions_challenge FOREIGN KEY (challenge_id) REFERENCES challenges(id) ON DELETE CASCADE;

-- challenges_submissions.challenge_instance_id → challenges_instances.id
ALTER TABLE challenges_submissions
    ADD CONSTRAINT fk_submissions_instance FOREIGN KEY (challenge_instance_id) REFERENCES challenges_instances(id) ON DELETE SET NULL;

-- logs.user_id → users.id
ALTER TABLE logs
    ADD CONSTRAINT fk_logs_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX unique_running_instance_per_team
ON challenges_instances(team_id, challenge_id)
WHERE status IN ('pending', 'running');