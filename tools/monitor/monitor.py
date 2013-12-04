#!/usr/bin/env python
#
# Copyright 2008 Jose Fonseca
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import gtk
import gtk.gdk
import xdot
import psycopg2
import string
from os import getenv
import re
from sys import exit
from datetime import datetime, date, time

# Database configuration
PGHOST= getenv('PGHOST', 'localhost')
PGPORT = string.atoi(getenv('PGPORT', "7099"))
PGUSER= getenv('PGUSER', 'postgres')
PGDATABASE = getenv('PGDATABASE', 'slonyregress1')
PGCLUSTER = getenv('PGCLUSTER', 'slony_regress1')
INITIALDBSOURCE="dbname=%s host=%s user=%s port=%d" % (PGDATABASE, PGHOST, PGUSER, PGPORT)
db=psycopg2.connect(INITIALDBSOURCE)
mcur=db.cursor()
mcur.execute("set search_path to \"_%s\";" % (PGCLUSTER))

class MyDotWindow(xdot.DotWindow):
    def mainnodescreen (self):
        qnodes = "select no_id, no_active, no_comment, no_failed from sl_node;"
        nodes=""
        mcur.execute(qnodes)
        for tuple in mcur:
            node=tuple[0]
            active=tuple[1]
            comment=tuple[2]
            failed=tuple[3]
            nodeline = "node%s [ label= \"node%s %s\", URL=\"node%s\" ]\n" % (node, node, comment, node)
            nodes = "%s\n%s\n" % (nodes, nodeline)
        now=datetime.now()
        metadata = "metadata [label=<<table><tr><td> DB Info</td> </tr><tr><td> DB </td> <td> %s </td> </tr> <tr><td> Host </td><td> %s </td></tr> <tr><td> User </td><td> %s </td></tr> <tr><td> Port </td><td> %s </td></tr> <tr><td> Date </td><td> %s </td></tr></table>> ];\n" % (PGDATABASE,PGHOST, PGUSER, PGPORT, now)
                                                                                     
        subscriptions=""
        qsubs = "select sub_set, sub_provider, sub_receiver, sub_forward, sub_active from sl_subscribe;"
        mcur.execute(qsubs)
        for tuple in mcur:
            subset=tuple[0]
            subprovider=tuple[1]
            subreceiver=tuple[2]
            subforward=tuple[3]
            subactive=tuple[4]
            if subforward:
                style="filled"
            else:
                style="dotted"
            if subactive:
                color="green"
            else:
                color="red"
            subline = "node%s -> node%s [style=%s, color=%s, label=\"set%s\", URL=\"set%s\"]\n" % (subreceiver, subprovider, style, color, subset, subset)
            subscriptions = "%s\n%s\n" % (subscriptions, subline)
        maindotcode = """
digraph G {
 subgraph cluster_Menus {
  node [shape=record, style=filled];
  quit [label =\"Quit\", URL=\"quit\", fillcolor=red]
  mainscreen [label=\"Main Screen", URL=\"mainscreen\", fillcolor=lightblue]
 }
 subgraph cluster_Metadata {
  label=\"DB Connection Info used to access cluster\";
  node [shape=Mrecord];
  %s
 }
 subgraph cluster_Nodes {
  label=\"Cluster subscription overview\";
  %s
  %s
 }
}
""" % (metadata, nodes, subscriptions)

        return maindotcode
        
    def __init__(self):
        xdot.DotWindow.__init__(self)
        self.widget.connect('clicked', self.on_url_clicked)

    def on_url_clicked(self, widget, url, event):
        nodesearch = re.search("^node(\d+)$", url)
        setsearch = re.search("^set(\d+)$", url)
        if (url == "quit"):
            exit()
        elif (url == "mainscreen"):
            self.widget.set_dotcode(self.mainnodescreen())
        elif nodesearch:
            self.widget.set_dotcode(self.nodedotcode(int(nodesearch.group(1))))
        elif setsearch:
            self.widget.set_dotcode(self.setdotcode(int(setsearch.group(1))))
        else:    
            dialog = gtk.MessageDialog(
                parent = self, 
                buttons = gtk.BUTTONS_OK,
                message_format="%s clicked" % url)
            dialog.connect('response', lambda dialog, response: dialog.destroy())
            dialog.run()
            return True

    def nodedotcode(self, nodeid):
        conninfoquery="select pa_conninfo from sl_path where pa_server=%d limit 1;" % (nodeid)
        mcur.execute(conninfoquery)
        nodeconninfo="none found"
        for tuple in mcur:
            nodeconninfo = tuple[0]
        if nodeconninfo == "none found":
            nodedata = """
subgraph cluster_NodeInfo {
  nodeinfo [label=\"|{ Node %d | No path found }|\"]
}
""" % (nodeid)
        else:
            # Now, search for some data about this node
            # all sets that this node is involved with...
            ndb=psycopg2.connect(nodeconninfo)
            ncur=ndb.cursor()
            ncur.execute("set search_path to \"_%s\";" % (PGCLUSTER))
            qsets="select set_id, set_origin, set_origin=%d from sl_set;" % (nodeid)
            ncur.execute(qsets)
            sets="""subgraph cluster_Sets {
 label="Sets in which node %d participates"
""" % (nodeid)
            for tuple in ncur:
                if tuple[2]:
                    setnode=" set%d [shape=record, label=\"set %d ORIGIN\" URL=\"set%s\", style=filled, fillcolor=green] " % (tuple[0], tuple[0], tuple[0])
                else:
                    setnode=" set%d [shape=record, label=\"set %d origin=node%s\", URL=\"set%s\"] " % (tuple[0], tuple[1], tuple[0], tuple[0])
                sets="%s\n%s" % (sets,setnode)
            sets="%s\n%s" % (sets, "}")

            nodedata = """
subgraph cluster_NodeInfo {
  nodeinfo [label=\"Node %d\", URL=\"node%d\"]
}
%s
""" % (nodeid, nodeid, sets)

            qnodes="select distinct con_origin from sl_confirm union select distinct con_received from sl_confirm;"
            qconfirms="select con_origin, con_received, min(con_seqno), max(con_seqno), count(*) from sl_confirm group by con_origin, con_received order by con_origin, con_received;"
            confirms = """
subgraph cluster_Confirms {
 label="Confirmations by node per node %d"
""" % (nodeid)
            ncur.execute(qnodes)
            for tuple in ncur:
                nodeline = "   node%s [label=\"node%s\", URL=\"node%s\" ];\n" % (tuple[0],tuple[0],tuple[0])
                confirms = "%s\n%s" % (confirms, nodeline)
            ncur.execute(qconfirms)
            for tuple in ncur:
                edgeline = "   node%s -> node%s [style=solid, label=\"events(%d,%d) count=%d\"];" % (tuple[1], tuple[0], tuple[2], tuple[3], tuple[4])
                confirms = "%s\n%s" % (confirms, edgeline)
            confirms="%s\n}\n" % (confirms)

            qthreads="select co_actor, co_node, co_activity, co_starttime, co_event, co_eventtype from sl_components order by co_actor;"
            ncur.execute(qthreads)
            threads="<tr> <td> Actor </td><td> Node </td> <td> Activity </td> <td>Latest Event Started</td> <td> Event ID </td> <td> Event Type </td> </tr>"
            for tuple in ncur:
                threadentry = "<tr><td> %s </td><td> %s </td><td> %s </td><td> %s </td><td> %s </td><td> %s </td></tr>" % (tuple[0], tuple[1], tuple[2], tuple[3], tuple[4], tuple[5])
                threads="%s %s" % (threads, threadentry)

            threadgraph="""
subgraph cluster_ThreadInfo {
   threadsnode [label=<<table> %s </table>>, shape=record];
}
""" % (threads)

            qconfig="select relname, relpages, reltuples from pg_class, pg_namespace n where relnamespace = n.oid and nspname = '_%s' and relkind = 'r' order by relpages desc;" % (PGCLUSTER)
            ncur.execute(qconfig)
            ctables="<tr> <td> Table </td> <td> # pages </td> <td> # tuples </td> </tr>"
            for tuple in ncur:
                ctentry="<tr><td> %s </td><td> %s </td><td> %s </td></tr>" % (tuple[0], tuple[1], tuple[2])
                ctables="%s %s" % (ctables, ctentry)
            tablegraph="tablesizes [label=<<table> %s </table>>, shape=record];" % (ctables)

            lnodes=""
            qnodes="select no_id from sl_node;"
            ncur.execute (qnodes)
            for tuple in ncur:
                nline="lnode%s [label=\"node%s\", URL=\"node%s\"];" % (tuple[0], tuple[0], tuple[0])
                lnodes="%s\n%s" % (lnodes, nline)
            lpaths=""
            qlistens="select li_provider, li_receiver from sl_listen where li_origin=%d;" % (nodeid)
            ncur.execute (qlistens)
            for tuple in ncur:
                lline="lnode%s -> lnode%s;" % (tuple[1], tuple[0])
                lpaths="%s\n%s" % (lpaths, lline)

            listengraph="""
subgraph cluster_Listeners {
label="Listen Network - how each node listens for events from node %d";
%s
%s
}
""" % (nodeid, lnodes, lpaths)

        nodedot = """
digraph G {
 subgraph cluster_Menus {
  rank = same;
  node [shape=record];
  quit [label =\"Quit\", URL=\"quit\", style=filled, fillcolor=red]
  mainscreen [label=\"Main Screen", URL=\"mainscreen\", style=filled, fillcolor=lightblue]
 }
 %s
 %s
 %s
 %s
 %s
}
""" % (tablegraph, confirms, threadgraph, nodedata, listengraph)
        print nodedot
        return nodedot
    def setdotcode(self, setid):
        # connect to origin node
        conninfoquery="select pa_conninfo from sl_path, sl_set where set_id = %d and pa_server=set_origin limit 1;" % (setid)
        mcur.execute(conninfoquery)
        nodeconninfo="none found"
        for tuple in mcur:
            nodeconninfo = tuple[0]
        if nodeconninfo == "none found":
            nodedata = """
subgraph cluster_SetInfo {
  nodeinfo [label=\"|{ Set %d | No path found }|\"]
}
""" % (setid)
        else:
            # Now, search for some data about this set
            # all sets that this node is involved with...
            ndb=psycopg2.connect(nodeconninfo)
            ncur=ndb.cursor()
            ncur.execute("set search_path to \"_%s\";" % (PGCLUSTER))
            qset="select now(), ev_seqno, (select count(*) from sl_table where tab_set = ev_origin) from sl_event where ev_origin = %d order by ev_seqno desc limit 1;" % (setid)
            ncur.execute(qset)
            for tuple in ncur:
                setinfo=" set%d [label=\"|{ Set %d | As at %s | Latest event %s | # of tables: %s }|\", URL=\"set%d\"]" % (setid, setid, tuple[0], tuple[1], tuple[2], setid)

            qtables="select tab_id, quote_ident(tab_nspname) || '.' || quote_ident(tab_relname), tab_comment, relpages, reltuples from sl_table t1, pg_catalog.pg_class c where tab_set=%d and c.oid = tab_reloid order by tab_id;" % (setid)
            ncur.execute(qtables)
            tables= "<tr><td>Table ID</td><td>Table Name</td><td>Description</td><td>Pages</td><td>Approx Tuples</td></tr>"
            for tuple in ncur:
                tableline="<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (tuple[0], tuple[1], tuple[2], tuple[3], tuple[4])
                tables = "%s %s" % (tables, tableline)

            qsequences="select seq_id, quote_ident(seq_nspname) || '.' || quote_ident(seq_relname), seq_comment from sl_sequence where seq_set=%d order by seq_id;" % (setid)
            ncur.execute(qsequences)
            sequences = "<tr><td>Seq ID</td><td>Sequence Name</td><td>Description</td></tr>"
            for tuple in ncur:
                sline="<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (tuple[0], tuple[1], tuple[2])
                sequences = "%s %s" % (sequences, sline)

            objectgraph="""
subgraph cluster_ObjectInfo {
    label="Objects in set %d";
    tablesnode [label=<<table> %s </table>>, shape=record];
    sequencesnode [label=<<table> %s </table>>, shape=record];
}
""" % (setid, tables, sequences)
            

            qnodes="select sub_receiver, sub_forward, sub_active, 'f' as originp from sl_subscribe where sub_set = %d union select set_origin, 't', 't', 't' from sl_set where set_id = %d;" % (setid, setid)
            ncur.execute(qnodes)
            nodes="""
subgraph cluster_Subscription {
label="Subscription information for set %d";
""" % (setid)
            for tuple in ncur:
                lnodeid=tuple[0]
                if tuple[1]:
                    lforward=" style=filled, fillcolor=blue "
                else:
                    lforward=" style=filled, fillcolor=red "
                if tuple[3]=='t':
                    lforward=" style=filled, fillcolor=green "
                else:
                    lforward=lforward
                if tuple[2]:
                    lforward=lforward
                else:
                    lforward=" style=filled, fillcolor=red "
                nodeline="node%s [label=\"node%s\" URL=\"node%s\", %s]" % (lnodeid, lnodeid, lnodeid, lforward)
                nodes="%s\n%s\n" % (nodes, nodeline)
            qsubscribers="select sub_provider, sub_receiver, sub_active, st_lag_num_events, st_lag_time from sl_subscribe, sl_status where sub_set = %d and st_received = sub_receiver;" % (setid)
            ncur.execute(qsubscribers)
            for ntuple in ncur:
                lprovider=ntuple[0]
                lreceiver=ntuple[1]
                lactive=ntuple[2]
                lagnum=ntuple[3]
                lagtime=ntuple[4]
                if ntuple[2]:
                    estyle="solid"
                else:
                    estyle="dotted"
                edgeline="node%s -> node%s [style=%s, label=\"event lag=(%s,%s)\"]" % (lreceiver, lprovider, estyle, lagnum, lagtime)
                nodes="%s\n%s\n" % (nodes, edgeline)
            nodes= "%s\n}\n" % (nodes)

        nodedot = """
digraph G {
 subgraph cluster_Menus {
  node [shape=record];
  quit [label =\"Quit\", URL=\"quit\", style=filled, fillcolor=red]
  %s
  %s
  mainscreen [label=\"Main Screen", URL=\"mainscreen\", style=filled, fillcolor=lightblue]
 }
 %s
}
""" % (setinfo, objectgraph, nodes)
        print nodedot
        return nodedot


def main():
    window = MyDotWindow()
    print window.mainnodescreen()
    window.set_dotcode(window.mainnodescreen())
    window.connect('destroy', gtk.main_quit)
    gtk.main()

if __name__ == '__main__':
    main()
