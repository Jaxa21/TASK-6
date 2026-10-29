# Faker SQL

PostgreSQL stored procedures in the `faker` schema that generate data for Poland (`pl_PL`) and Norway (`nb_NO`). 
Its also returning rows from functions, not `PROCEDURE`s.

```bash
psql "$DATABASE_URL" -f sql/schema.sql -f sql/functions.sql -f sql/data.sql
```

```sql
SELECT * FROM faker.fake_users('pl_PL', 42, 0);   -- 10 people
SELECT * FROM faker.fake_users('pl_PL', 42, 1);   -- next 10
```

## Main procedures

| Procedure | Arguments | Returns |
|---|---|---|
| `fake_users(locale, seed, batch, size = 10)` | `locale text`, `seed bigint`, `batch bigint ≥ 0`, `size int` 1–100,000 | `pos`, `full_name`, `gender`, `address`, `latitude`, `longitude`, `height_cm`, `weight_kg`, `eye_color`, `hair_color`, `phone`, `email` |
| `benchmark(locale, users = 10000)` | `locale text`, `users int` | `users`, `seconds`, `users_per_second` |

**Reproducibility.** For every person, `fake_users` calls `setseed(person_seed(locale, seed, position))`. All later values come from `random()` in a fixed order, so the same locale, seed, batch and index always give the same output.

## Helper procedures

All helpers use `random()`. 
`setseed(x)` can be use to repeat a result.

| Procedure | Description |
|---|---|
| `person_seed(locale, seed, position) → float8` | First 63 bits of `md5('locale\|seed\|position')`, scaled to [−1, 1] for `setseed` |
| `rand_int(lo, hi) → int` | Uniform integer |
| `rand_normal(mean, sd) → float8` | Normal value (Box–Muller) |
| `random_point() → (latitude, longitude)` | Point uniformly distributed on the sphere |
| `pick(locale, category, gender = 'U') → text` | Weighted random value from `words`; gender `M`/`F` also includes `U` rows |
| `picks(locale, category, gender, n) → text[]` | `n` values from `pick` |
| `pick_city(locale) → faker.cities` | City weighted by population |
| `numerify(text) → text` | Replaces each `#` with a random digit |
| `fill(format, values jsonb) → text` | Replaces each `{key}` with its value |
| `token_count(format, token) → int` | Highest number of a token, e.g. `{first3}` → 3 |
| `numbered(token, values text[]) → jsonb` | `{first, first2, first3 …}` keys for `fill` |
| `has_duplicates(values text[]) → boolean` | True if a value repeats |
| `slugify(text) → text` | ASCII e-mail part: `Łukasz Øvre` → `lukasz.ovre` |
| `gen_name(locale, gender) → (full_name, first_name, last_name)` | Name from a weighted name format |
| `gen_address(locale) → text` | Street, building, flat, postcode and city in an address format |
| `gen_phone(locale) → text` | Phone format with random digits |
| `gen_email(locale, first, last) → text` | E-mail format with the names and a local domain |
| `gen_measure(locale, gender, attribute) → numeric` | `height_cm` or `weight_kg` from `rand_normal`, clamped to [min, max] |

## Algorithms

**Normal distribution (Box–Muller).** For uniform u₁, u₂: `z = sqrt(−2 ln u₁) · cos(2π u₂)` is N(0, 1), and `x = mean + sd · z`. Mean and sd al calculated from `body_stats` per locale and gender.

**Uniform points on the sphere.** The area between two latitudes is proportional to the difference of their sines, so sin(latitude) must be uniform: `latitude = asin(2u₁ − 1)`, `longitude = 360u₂ − 180`.

**Weighted choice.**  The view `word_pools` stores each row's running share of the total, in (0, 1]. `pick` returns the first row whose share exceeds `random()`, so each row is chosen with probability weight / total.

**Name generation.** Gender is drawn first and passed to every pick, so names, surnames forms (Kowalski / Kowalska) and titles agree. The layout comes from weighted `name_format` rows with these tokens: `{first}`, `{first2}` … `{firstN}`, `{last}`, `{last2}` … `{lastN}`, `{title}`, `{initial}`. The highest number decides how many names are drawn, so any number of first names and surnames is possible. If a name repeats, the format falls back to `{first} {last}`.

## Data 

Every table has a `locale` column that covers, `words` (names, streets, titles, colours, domains and all formats, with `category`, `gender`, `weight`), `cities`, `body_stats`. A new locale or format is only new rows, followed by `REFRESH MATERIALIZED VIEW faker.word_pools;`.

```sql
INSERT INTO faker.words (locale, category, value, weight) VALUES ('pl_PL', 'name_format', '{first} {first2} {first3} {last}', 1);
REFRESH MATERIALIZED VIEW faker.word_pools;
```

Part of the names and streets comes from [Faker](https://github.com/joke2k/faker) (`pl_PL`, `no_NO`, MIT licence).
