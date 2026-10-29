CREATE FUNCTION faker.person_seed(p_locale text, p_seed bigint, p_position bigint)
RETURNS float8 LANGUAGE sql IMMUTABLE AS $$
    SELECT ('x' || substr(md5(p_locale || '|' || p_seed || '|' || p_position), 1, 16))::bit(64)::bigint
           / 9223372036854775807.0
$$;

CREATE FUNCTION faker.rand_int(lo int, hi int)
RETURNS int LANGUAGE sql AS $$
    SELECT lo + floor(random() * (hi - lo + 1))::int
$$;

CREATE FUNCTION faker.rand_normal(mean float8, sd float8)
RETURNS float8 LANGUAGE sql AS $$
    SELECT mean + sd * sqrt(-2 * ln(1 - random())) * cos(2 * pi() * random())
$$;

CREATE FUNCTION faker.rand_point(OUT latitude float8, OUT longitude float8)
LANGUAGE sql AS $$
    SELECT degrees(asin(2 * random() - 1)), 360 * random() - 180
$$;

CREATE FUNCTION faker.pick(p_locale text, p_category text, p_gender text DEFAULT 'U')
RETURNS text LANGUAGE sql AS $$
    SELECT value FROM faker.word_pools
    WHERE locale = p_locale AND category = p_category AND gender = p_gender AND upto > (SELECT random())
    ORDER BY upto LIMIT 1
$$;

CREATE FUNCTION faker.picks(p_locale text, p_category text, p_gender text, n int)
RETURNS text[] LANGUAGE sql AS $$
    SELECT array(SELECT faker.pick(p_locale, p_category, p_gender) FROM generate_series(1, n))
$$;

CREATE FUNCTION faker.pick_city(p_locale text)
RETURNS faker.cities LANGUAGE sql AS $$
    SELECT id, locale, city, postcode_pattern, region, weight
    FROM (SELECT *, sum(weight) OVER (ORDER BY id) / sum(weight) OVER () AS upto
          FROM faker.cities WHERE locale = p_locale) t
    WHERE upto > (SELECT random())
    ORDER BY upto LIMIT 1
$$;

CREATE FUNCTION faker.numerify(p text)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    WHILE strpos(p, '#') > 0 LOOP
        p := overlay(p PLACING faker.rand_int(0, 9)::text FROM strpos(p, '#') FOR 1);
    END LOOP;
    RETURN p;
END $$;

CREATE FUNCTION faker.fill(fmt text, vals jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE kv record;
BEGIN
    FOR kv IN SELECT * FROM jsonb_each_text(vals) LOOP
        fmt := replace(fmt, '{' || kv.key || '}', coalesce(kv.value, ''));
    END LOOP;
    RETURN fmt;
END $$;

CREATE FUNCTION faker.token_count(fmt text, token text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(max(m[1]::int), 1) FROM regexp_matches(fmt, '\{' || token || '(\d+)\}', 'g') m
$$;

CREATE FUNCTION faker.numbered(token text, vals text[])
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(jsonb_object_agg(CASE WHEN i = 1 THEN token ELSE token || i END, v), '{}')
    FROM unnest(vals) WITH ORDINALITY u(v, i)
$$;

CREATE FUNCTION faker.has_duplicates(vals text[])
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT count(*) <> count(DISTINCT v) FROM unnest(vals) v
$$;

CREATE FUNCTION faker.slugify(t text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT btrim(regexp_replace(regexp_replace(replace(lower(unaccent(t)), ' ', '.'),
                 '[^a-z0-9._-]', '', 'g'), '[._-]{2,}', '.', 'g'), '._-')
$$;

CREATE FUNCTION faker.gen_name(p_locale text, p_gender text,
                               OUT full_name text, OUT first_name text, OUT last_name text)
LANGUAGE plpgsql AS $$
DECLARE
    fmt    text   := faker.pick(p_locale, 'name_format');
    firsts text[] := ARRAY[faker.pick(p_locale, 'first_name', p_gender)];
    lasts  text[] := ARRAY[faker.pick(p_locale, 'last_name', p_gender)];
    title  text;
BEGIN
    firsts := firsts || faker.picks(p_locale, 'first_name', p_gender, faker.token_count(fmt, 'first') - 1);
    lasts  := lasts || faker.picks(p_locale, 'last_name', p_gender, faker.token_count(fmt, 'last') - 1);
    IF fmt LIKE '%{title}%' THEN
        title := faker.pick(p_locale, 'title', p_gender);
    END IF;
    IF faker.has_duplicates(firsts) OR faker.has_duplicates(lasts) THEN
        fmt := '{first} {last}';
    END IF;
    first_name := firsts[1];
    last_name := lasts[1];
    full_name := faker.fill(fmt, faker.numbered('first', firsts) || faker.numbered('last', lasts)
                 || jsonb_build_object('title', title, 'initial', left(first_name, 1) || '.'));
END $$;

CREATE FUNCTION faker.gen_address(p_locale text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    c   faker.cities := faker.pick_city(p_locale);
    fmt text := faker.numerify(faker.pick(p_locale, 'address_format'));
BEGIN
    RETURN faker.fill(fmt, jsonb_build_object(
        'street', faker.pick(p_locale, 'street'),
        'building', faker.rand_int(1, 120),
        'flat', faker.rand_int(1, 80),
        'postcode', faker.numerify(c.postcode_pattern),
        'city', c.city, 'CITY', upper(c.city), 'region', c.region));
END $$;

CREATE FUNCTION faker.gen_phone(p_locale text)
RETURNS text LANGUAGE sql AS $$
    SELECT faker.numerify(faker.pick(p_locale, 'phone_format'))
$$;

CREATE FUNCTION faker.gen_email(p_locale text, p_first text, p_last text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    fmt   text := faker.numerify(faker.pick(p_locale, 'email_format'));
    login text := faker.slugify(faker.fill(fmt, jsonb_build_object(
                      'first', p_first, 'last', p_last, 'f', left(p_first, 1), 'l', left(p_last, 1))));
BEGIN
    IF login = '' THEN
        login := 'user' || faker.rand_int(1000, 9999);
    END IF;
    RETURN login || '@' || faker.pick(p_locale, 'email_domain');
END $$;

CREATE FUNCTION faker.gen_measure(p_locale text, p_gender text, p_attribute text)
RETURNS numeric LANGUAGE sql AS $$
    SELECT round(least(greatest(faker.rand_normal(mean, sd), min_value), max_value)::numeric, 1)
    FROM faker.body_stats
    WHERE locale = p_locale AND gender = p_gender AND attribute = p_attribute
$$;

CREATE FUNCTION faker.fake_users(p_locale text, p_seed bigint, p_batch bigint, p_size int DEFAULT 10)
RETURNS TABLE (pos bigint, full_name text, gender text, address text,
               latitude float8, longitude float8, height_cm numeric, weight_kg numeric,
               eye_color text, hair_color text, phone text, email text)
LANGUAGE plpgsql AS $$
DECLARE
    female float8;
    n      record;
BEGIN
    SELECT p_female INTO female FROM faker.locales WHERE code = p_locale;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown locale "%"', p_locale;
    END IF;
    IF p_batch < 0 OR p_size NOT BETWEEN 1 AND 100000 THEN
        RAISE EXCEPTION 'batch must be >= 0 and size between 1 and 100000';
    END IF;
    FOR i IN 0 .. p_size - 1 LOOP
        pos := p_batch * p_size + i;
        PERFORM setseed(faker.person_seed(p_locale, p_seed, pos));
        gender := CASE WHEN random() < female THEN 'F' ELSE 'M' END;
        n := faker.gen_name(p_locale, gender);
        full_name := n.full_name;
        address := faker.gen_address(p_locale);
        SELECT round(p.latitude::numeric, 6), round(p.longitude::numeric, 6)
        INTO latitude, longitude FROM faker.rand_point() p;
        height_cm := faker.gen_measure(p_locale, gender, 'height_cm');
        weight_kg := faker.gen_measure(p_locale, gender, 'weight_kg');
        eye_color := faker.pick(p_locale, 'eye_color');
        hair_color := faker.pick(p_locale, 'hair_color');
        phone := faker.gen_phone(p_locale);
        email := faker.gen_email(p_locale, n.first_name, n.last_name);
        RETURN NEXT;
    END LOOP;
END $$;

CREATE FUNCTION faker.benchmark(p_locale text, p_users int DEFAULT 10000, OUT users_per_second numeric)
LANGUAGE plpgsql AS $$
DECLARE
    t0 timestamptz := clock_timestamp();
BEGIN
    PERFORM count(*) FROM faker.fake_users(p_locale, 1, 0, p_users);
    users_per_second := round(p_users / extract(epoch FROM clock_timestamp() - t0));
END $$;
