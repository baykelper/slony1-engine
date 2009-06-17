#!/bin/bash
# $Id: slonikconfdump.sh,v 1.1.2.3 2009-06-12 22:42:13 cbbrowne Exp $
# This tool rummages through a Slony-I cluster, generating a slonik script
# suitable to recreate the cluster

# Start with:
# SLONYCLUSTER indicating the cluster name
echo "# building slonik config files for cluster ${SLONYCLUSTER}"
echo "# generated by: slonikconfdump.sh"
echo "# Generated on: " `date`
SS="\"_${SLONYCLUSTER}\""
echo "cluster name=${SLONYCLUSTER};"

function RQ () {
    local QUERY=$1
    RESULTSET=`psql -qtA -F ":" -R " " -c "${QUERY}"`
    echo ${RESULTSET}
}
function argn () {
    local V=$1
    local n=$2
    local res=`echo ${V} | cut -d : -f ${n}`
    echo $res
}
    
function arg1 () {
    echo `argn "$1" 1`
}
function arg2 () {
    echo `argn "$1" 2`
}
function arg3 () {
    echo `argn "$1" 3`
}

Q="select distinct pa_server from ${SS}.sl_path order by pa_server;"
PATHS=`RQ "${Q}"`
for svr in `echo ${PATHS}`; do
    SQ="select pa_conninfo from ${SS}.sl_path where pa_server=${svr} order by pa_client asc limit 1;"
    conninfo=`RQ "${SQ}"`
    echo "node ${svr} admin conninfo='${conninfo}';"
done

Q="select no_id, no_comment from ${SS}.sl_node order by no_id limit 1;"

NODE1=`RQ "${Q}"`
nn=`arg1 "${NODE1}"`
comment=`arg2 ${NODE1}`
echo "init cluster (id=${nn}, comment='${comment}');"

Q="select no_id from ${SS}.sl_node order by no_id offset 1;"
NODES=`RQ "${Q}"`
for node in `echo ${NODES}`; do
    CQ="select no_comment from ${SS}.sl_node where no_id = ${node};"
    comment=`RQ "${CQ}"`
    echo "store node (id=${node}, comment='${comment}');"
done

Q="select pa_server, pa_client, pa_connretry from ${SS}.sl_path order by pa_server, pa_client;"
PATHS=`RQ "${Q}"`
for sc in `echo $PATHS`; do
    server=`arg1 $sc`
    client=`arg2 $sc`
    retry=`arg3 $sc`
    Q2="select pa_conninfo from ${SS}.sl_path where pa_server=${server} and pa_client=${client};"
    conninfo=`RQ "${Q2}"`
    echo "store path (server=${server}, client=${client}, conninfo='${conninfo}', connretry=${retry});"
done

Q="select set_id, set_origin from ${SS}.sl_set order by set_id;"
SETS=`RQ "${Q}"`
for sc in `echo ${SETS}`; do
    set=`arg1 ${sc}`
    origin=`arg2 ${sc}`
    Q2="select set_comment from ${SS}.sl_set where set_id=${set};"
    comment=`RQ "${Q2}"`
    echo "create set (id=${set}, origin=${origin}, comment='${comment}');"
done

Q="select tab_id,tab_set, set_origin from ${SS}.sl_table, ${SS}.sl_set where tab_set = set_id order by tab_id;"
TABS=`RQ "${Q}"`
for tb in `echo ${TABS}`; do
    tab=`arg1 ${tb}`
    set=`arg2 ${tb}`
    origin=`arg3 ${tb}`
    RQ="select tab_relname from ${SS}.sl_table where tab_id = ${tab};"
    relname=`RQ "${RQ}"`
    NSQ="select tab_nspname from ${SS}.sl_table where tab_id = ${tab};"
    nsp=`RQ "${NSQ}"`
    IDX="select tab_idxname from ${SS}.sl_table where tab_id = ${tab};"
    idx=`RQ "${IDX}"`
    COM="select tab_comment from ${SS}.sl_table where tab_id = ${tab};"
    comment=`RQ "${COM}"`
    echo "set add table (id=${tab}, set id=${set}, origin=${origin}, fully qualified name='\"${nsp}\".\"${relname}\"', comment='${comment}, key='${idx}');"
done


Q="select seq_id,seq_set,set_origin from ${SS}.sl_sequence, ${SS}.sl_set where seq_set = set_id order by seq_id;"
SEQS=`RQ "${Q}"`
for sq in `echo ${SEQS}`; do
    seq=`arg1 ${sq}`
    set=`arg2 ${sq}`
    origin=`arg3 ${sq}`
    RELQ="select seq_relname from ${SS}.sl_sequence where seq_id = ${seq};"
    relname=`RQ "${RELQ}"`
    NSQ="select seq_nspname from ${SS}.sl_sequence where seq_id = ${seq};"
    nsp=`RQ "${NSQ}"`
    COM="select seq_comment from ${SS}.sl_sequence where seq_id = ${seq};"
    comment=`RQ "${COM}"`
    echo "set add sequence(id=${seq}, set id=${set}, origin=${origin}, fully qualified name='\"${nsp}\".\"${relname}\"', comment='${comment}');"
done

Q="select set_id, set_origin from ${SS}.sl_set;"
SETS=`RQ "${Q}"`
for seti in `echo ${SETS}`; do
    set=`arg1 ${seti}`
    origins=`arg2 ${seti}`
    SUBQ="select sub_provider, sub_receiver from ${SS}.sl_subscribe where sub_set=${set};"
    # We use tsort to determine a feasible ordering for subscriptions
    SUBRES=`psql -qtA -F " " -c "${SUBQ}" | tsort | egrep -v "^${origin}\$"`
    for recv in `echo ${SUBRES}`; do
	SF="select sub_provider, sub_forward from ${SS}.sl_subscribe where sub_set=${set} and sub_receiver=${recv};"
	SR=`RQ "${SF}"`
	prov=`arg1 ${SR}`
	forw=`arg2 ${SR}`
	echo "subscribe set (id=${set}, provider=${prov}, receiver=${recv}, forward=${forw}, omit copy=true);"
	if [ $prov != $origin ]; then
	    echo "wait for event (origin=$provider, confirmed=$origin, wait on=$provider, timeout=0);"
	fi
	echo "sync (id=$origin);"
	echo "wait for event (origin=$origin, confirmed=ALL, wait on=$origin, timeout=0);"
    done
done