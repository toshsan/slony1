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

class MyDotWindow(xdot.DotWindow):
    def mainnodescreen (self):
        qnodes = "select no_id, no_active, no_comment, no_failed from \"_%s\".sl_node;" % (PGCLUSTER)
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
        metadata = "metadata [label=\"|{ |{ DB Info }| |{ DB| %s }| {| Host | %s |} |{ User | %s }| |{ Port | %s }| |{ Date | %s }| }| \"];\n" % (PGDATABASE,PGHOST, PGUSER, PGPORT, now)
                                                                                     
        subscriptions=""
        qsubs = "select sub_set, sub_provider, sub_receiver, sub_forward, sub_active from \"_%s\".sl_subscribe;" % (PGCLUSTER)
        mcur.execute(qsubs)
        for tuple in mcur:
            subset=tuple[0]
            subprovider=tuple[1]
            subreceiver=tuple[2]
            subforward=tuple[3]
            subactive=tuple[4]
            subline = "node%s -> node%s\n" % (subreceiver, subprovider)
            subscriptions = "%s\n%s\n" % (subscriptions, subline)

        maindotcode = """
digraph G {
 subgraph Menus {
  rank = same;
  node [shape=record];
  quit [label =\"Quit\", URL=\"quit\", style=filled, fillcolor=red]
  mainscreen [label=\"Main Screen", URL=\"mainscreen\", style=filled, fillcolor=lightblue]
 }
 subgraph Metadata {
  rank = same;
  node [shape=Mrecord];
  %s
 }
 subgraph Nodes {
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
        if (url == "quit"):
            exit()
        elif (url == "mainscreen"):
            # dialog = gtk.MessageDialog(
            #     parent = self, 
            #     buttons = gtk.BUTTONS_OK,
            #     message_format="head to main screen")
            # dialog.connect('response', lambda dialog, response: dialog.destroy())
            self.widget.set_dotcode(self.mainnodescreen())
            #dialog.run()
        elif nodesearch:
            # dialog = gtk.MessageDialog(
            #     parent = self, 
            #     buttons = gtk.BUTTONS_OK,
            #     message_format=("head to node %s screen" % (nodesearch.group(1))))
            # dialog.connect('response', lambda dialog, response: dialog.destroy())
            self.widget.set_dotcode(self.nodedotcode(int(nodesearch.group(1))))
            #dialog.run()
            #dotnodecode(widget, nodesearch.group(1))
        else:    
            dialog = gtk.MessageDialog(
                parent = self, 
                buttons = gtk.BUTTONS_OK,
                message_format="%s clicked" % url)
            dialog.connect('response', lambda dialog, response: dialog.destroy())
            dialog.run()
            return True

    def nodedotcode(self, nodeid):
        conninfoquery="select pa_conninfo from \"_%s\".sl_path where pa_server=%d limit 1;" % (PGCLUSTER,nodeid)
        mcur.execute(conninfoquery)
        nodeconninfo="none found"
        for tuple in mcur:
            nodeconninfo = tuple[0]
        if nodeconninfo == "none found":
            nodedata = """
subgraph NodeInfo {
  nodeinfo [label=\"|{ Node %d | No path found }|\"]
}
""" % (nodeid)
        else:
            # Now, search for some data about this node
            # all sets that this node is involved with...
            ndb=psycopg2.connect(nodeconninfo)
            ncur=ndb.cursor()
            qsets="select set_id, set_origin = %d as originp from \"_%s\".sl_set;" % (nodeid,PGCLUSTER)
            ncur.execute(qsets)
            sets="subgraph Sets {"
            for tuple in ncur:
                if tuple[1]:
                    setnode=" set%d [shape=record, label=\"set %d ORIGIN\" URL=\"set%s\", style=filled, fillcolor=lightgreen] " % (tuple[0], tuple[0], tuple[0])
                else:
                    setnode=" set%d [shape=record, label=\"set %d\", URL=\"set%s\"] " % (tuple[0], tuple[0], tuple[0])
                sets="%s\n%s" % (sets,setnode)
            sets="%s\n%s" % (sets, "}")

            nodedata = """
subgraph NodeInfo {
  nodeinfo [label=\"|{ Node %d }|\"]
}
%s
""" % (nodeid, sets)
            
        nodedot = """
digraph G {
 subgraph Menus {
  rank = same;
  node [shape=record];
  quit [label =\"Quit\", URL=\"quit\"]
  mainscreen [label=\"Main Screen", URL=\"mainscreen\"]
 }
 %s
}
""" % (nodedata)

        return nodedot


def main():
    window = MyDotWindow()
    print window.mainnodescreen()
    window.set_dotcode(window.mainnodescreen())
    window.connect('destroy', gtk.main_quit)
    gtk.main()

if __name__ == '__main__':
    main()
