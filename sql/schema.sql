SET client_min_messages = warning;
DROP SCHEMA IF EXISTS faker CASCADE;
CREATE SCHEMA faker;
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE TABLE faker.locales (
    code      text PRIMARY KEY,
    name      text NOT NULL,
    p_female  float8 NOT NULL CHECK (p_female BETWEEN 0 AND 1)
);

CREATE TABLE faker.words (
    id        bigserial PRIMARY KEY,
    locale    text NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    category  text NOT NULL,
    gender    text NOT NULL DEFAULT 'U' CHECK (gender IN ('M', 'F', 'U')),
    value     text NOT NULL CHECK (btrim(value) <> ''),
    weight    float8 NOT NULL DEFAULT 1 CHECK (weight > 0),
    UNIQUE (locale, category, gender, value)
);

CREATE MATERIALIZED VIEW faker.word_pools AS
SELECT w.locale, w.category, g.gender, w.value,
       sum(w.weight) OVER (PARTITION BY w.locale, w.category, g.gender ORDER BY w.id)
     / sum(w.weight) OVER (PARTITION BY w.locale, w.category, g.gender) AS upto
  FROM faker.words w
  JOIN (VALUES ('M'), ('F'), ('U')) AS g(gender) ON w.gender IN (g.gender, 'U')
WITH NO DATA;
CREATE INDEX ON faker.word_pools (locale, category, gender, upto);

CREATE TABLE faker.cities (
    id                bigserial PRIMARY KEY,
    locale            text NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    city              text NOT NULL CHECK (btrim(city) <> ''),
    postcode_pattern  text NOT NULL,
    region            text NOT NULL,
    weight            float8 NOT NULL DEFAULT 1 CHECK (weight > 0),
    UNIQUE (locale, city)
);

CREATE TABLE faker.body_stats (
    locale     text NOT NULL REFERENCES faker.locales ON DELETE CASCADE,
    attribute  text NOT NULL,
    gender     text NOT NULL CHECK (gender IN ('M', 'F')),
    mean       float8 NOT NULL,
    sd         float8 NOT NULL CHECK (sd >= 0),
    min_value  float8 NOT NULL,
    max_value  float8 NOT NULL,
    PRIMARY KEY (locale, attribute, gender)
);
