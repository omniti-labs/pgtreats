#!/usr/bin/env bash

if ! psql -qAtX -c "select 1" &>/dev/null
then
    echo "Cannot connect to PostgreSQL database using current PG* settings:" >&2
    set | grep ^PG >&2
    exit 1
fi

# Makes sorting much faster
export LC_ALL=C

timestamping_awk='{print strftime("%Y-%m-%d %H:%M:%S :"), $0; fflush();}'
exec > >( awk "$timestamping_awk" ) 2>&1
logging_process_pid="$!"

current_db="$( psql -qAtX -c "select current_database()" )"
current_user="$( psql -qAtX -c "select current_user" )"

tmp_dir="$( mktemp -d )"
trap 'rm -rf "$tmp_dir"; kill $logging_process_pid' EXIT

df_line="$( df -hP "$tmp_dir" | tail -n 1 )"
df_available="$( echo "$df_line" | awk '{print $4}' )"
df_mount="$( echo "$df_line" | awk '{print $NF}' )"

echo "You are about to check database [$current_db], using account [$current_user]"
echo "Temporary files will be stored on $df_mount filesystem (in $tmp_dir directory). There is $df_available space available."
echo
echo -n "Do you want to continue? (type: \"yes\" to continue): "
read answer
if [[ ! "$answer" == "yes" ]]
then
    echo "Exiting."
    exit
fi

all_problems=""

echo "Testing Unique keys"
psql -qAtX -c "COPY (select c.oid, pg_get_indexdef( c.oid ), pg_size_pretty(pg_relation_size(c.oid))  from pg_namespace n join pg_class c on c.relnamespace = n.oid join pg_index i on c.oid = i.indexrelid where c.relkind = 'i' and i.indisunique order by pg_relation_size(c.oid) desc) TO STDOUT" > "$tmp_dir/indexes.lst"
index_count="$( wc -l "$tmp_dir/indexes.lst" | awk '{print $1}' )"

seq_scan_preamble="
set enable_bitmapscan = false;
set enable_indexonlyscan = false;
set enable_indexscan = false;
set enable_seqscan = true;
"

for i in $( seq 1 $index_count )
do
    idx_line="$( sed -ne "${i}p" "$tmp_dir/indexes.lst" )"
    idx_oid="$( echo "$idx_line" | cut -f1 )"
    idx_def="$( echo "$idx_line" | cut -f2 )"
    idx_size="$( echo "$idx_line" | cut -f3 )"
    echo "- Index $i/$index_count:"
    echo "  - def   : $idx_def"
    echo "  - size  : $idx_size"
    query="$( echo "$idx_def" | perl -ne '
    if ( /^.* ON (.*) USING [^ ]* \((.*)\) WHERE \((.*)\)\s*$/ ) {
        print "SELECT $2 FROM $1 WHERE $3\n";
    } elsif ( /^.* ON (.*) USING [^ ]* \((.*)\)\s*$/ ) {
        print "SELECT $2 FROM $1\n";
    }' )"
    if [[ -z "$query" ]]
    then
        echo "Cannot build query for this index?! Something is wrong." >&2
        continue
    fi
    echo "  - query : $query"
    echo "$seq_scan_preamble COPY ($query) TO STDOUT;" | \
        psql -qAtX | \
        perl -ne 'print unless /(^|\t)\\N($|\t)/' | \
        sort -S1G | \
        uniq -dc > "$tmp_dir/duplicates"

    if [[ -s "$tmp_dir/duplicates" ]]
    then
        echo "There are duplicates here:"
        cat "$tmp_dir/duplicates"
        all_problems="$all_problems- Index: $idx_def
"
    fi
    rm "$tmp_dir/duplicates"
done

echo "Testing Foreign keys"
echo "
COPY (
with con as (
    SELECT
        c.conname,
        c.conrelid::regclass as con_rel,
        c.conkey,
        c.confrelid::regclass as conf_rel,
        c.confkey,
        generate_subscripts(c.conkey, 1) as i
    FROM
        pg_constraint c
    WHERE
        c.contype = 'f'
)
SELECT
    c.con_rel,
    string_agg( quote_ident(a.attname), ', ' ORDER BY c.i ) as con_col,
    c.conf_rel,
    string_agg( quote_ident(fa.attname), ', ' ORDER BY c.i ) as conf_col
FROM
    con as c
    join pg_attribute a on c.con_rel = a.attrelid AND a.attnum = c.conkey[c.i]
    join pg_attribute fa on c.conf_rel = fa.attrelid AND fa.attnum = c.confkey[c.i]
WHERE
    pg_relation_size(c.con_rel) > 0
    and pg_relation_size(c.conf_rel) > 0
group BY
    c.conname,
    c.con_rel,
    c.conf_rel
ORDER BY pg_relation_size(c.conf_rel) + pg_relation_size(con_rel) desc
) TO STDOUT
" > "$tmp_dir/fkey-get-query"

psql -qAtX -f "$tmp_dir/fkey-get-query" | awk '!c[$0]++' > $tmp_dir/fkey-get-list
all_fkeys="$( cat $tmp_dir/fkey-get-list | wc -l )"
i=0
while IFS=$'\t' read r_table r_columns p_table p_columns
do
    rm -f "$tmp_dir/table_r.gz"
    rm -f "$tmp_dir/table_p.gz"

    i=$(( i + 1 ))
    echo "Fkey #$i / $all_fkeys):"
    echo "- $r_table ($r_columns) -=> $p_table ($p_columns)"

    echo "BEGIN;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    SET TRANSACTION READ ONLY;
    \o | sort -S1G -u | pigz -c - > $tmp_dir/table_r.gz
    COPY ( SELECT $r_columns FROM $r_table ) TO STDOUT;
    \o | sort -S1G -u | pigz -c - > $tmp_dir/table_p.gz
    COPY ( SELECT $p_columns FROM $p_table ) TO STDOUT;
    \o
    ROLLBACK;" | psql -qAtX
    bad_lines="$( comm -13 <( pigz -dc $tmp_dir/table_p.gz | perl -ne 'print unless /(^|\t)\\N($|\t)/' ) <( pigz -dc $tmp_dir/table_r.gz | perl -ne 'print unless /(^|\t)\\N($|\t)/' ) | wc -l )"
    if (( $bad_lines == 0 ))
    then
        continue
    fi
    echo "Bad values in $r_table ($r_columns) - not existing in $p_table ($p_columns) : $bad_lines different values. Sample:"
    comm -13 <( pigz -dc $tmp_dir/table_p.gz ) <( pigz -dc $tmp_dir/table_r.gz ) | head -n 5 | sed 's/^/- /'
    all_problems="$all_problems- Fkey: $r_table ($r_columns) -=> $p_table ($p_columns)
"
    echo
done < <( cat $tmp_dir/fkey-get-list )

if [[ -z "$all_problems" ]]
then
    echo "All OK."
else
    echo "Problems found:"
    echo "$all_problems"
fi
