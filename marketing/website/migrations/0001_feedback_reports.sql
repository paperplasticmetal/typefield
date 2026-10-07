CREATE TABLE IF NOT EXISTS feedback_reports (
  id TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('feedback', 'bug')),
  title TEXT NOT NULL CHECK (length(title) BETWEEN 5 AND 120),
  description TEXT NOT NULL CHECK (length(description) BETWEEN 20 AND 4000),
  steps TEXT NOT NULL CHECK (length(steps) <= 2000),
  reporter_email TEXT
);

CREATE INDEX IF NOT EXISTS feedback_reports_created_at_idx ON feedback_reports(created_at);
