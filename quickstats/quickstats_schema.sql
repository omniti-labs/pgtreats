--
-- PostgreSQL database dump
--

SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: quickstats; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA quickstats;


ALTER SCHEMA quickstats OWNER TO postgres;

SET search_path = quickstats, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: stats; Type: TABLE; Schema: quickstats; Owner: postgres; Tablespace:
--

CREATE TABLE stats (
    "timestamp" timestamp without time zone DEFAULT now() NOT NULL,
    ins integer,
    upd integer,
    del integer,
    txn integer,
    db text
);


ALTER TABLE quickstats.stats OWNER TO postgres;

--
-- Name: gather(); Type: FUNCTION; Schema: quickstats; Owner: postgres
--

CREATE FUNCTION gather() RETURNS SETOF void
    AS $$ insert into quickstats.stats select now(), sum(n_tup_ins) as ins, sum(n_tup_upd) as upd, sum(n_tup_del) as del, (select xact_commit from pg_catalog.pg_
stat_database where datname=(select current_database())) as xact_commit, current_database() from pg_stat_all_tables $$
    LANGUAGE sql;


ALTER FUNCTION quickstats.gather() OWNER TO postgres;

--
-- PostgreSQL database dump complete
--
