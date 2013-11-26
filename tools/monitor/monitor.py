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


class MyDotWindow(xdot.DotWindow):
    def mainnodescreen (self):
        INITIALDBSOURCE="dbname=%s host=%s user=%s port=%d" % (PGDATABASE, PGHOST, PGUSER, PGPORT)
        db=psycopg2.connect(INITIALDBSOURCE)
        cur=db.cursor()
        qnodes = "select no_id, no_active, no_comment, no_failed from \"_%s\".sl_node;" % (PGCLUSTER)
        nodes=""
        cur.execute(qnodes)
        for tuple in cur:
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
        cur.execute(qsubs)
        for tuple in cur:
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
            self.widget.set_dotcode(self.nodedotcode(nodesearch.group(1)))
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
        a=nodeid
        nodedot = """
digraph G {
 subgraph Menus {
  rank = same;
  node [shape=record];
  quit [label =\"Quit\", URL=\"quit\"]
  mainscreen [label=\"Main Screen", URL=\"mainscreen\"]
 }
 subgraph NodeInfo {
  nodeinfo [label=\"Node %s\"]
 }
}
""" % (nodeid)

        return nodedot


def main():
    window = MyDotWindow()
    print window.mainnodescreen()
    window.set_dotcode(window.mainnodescreen())
    window.connect('destroy', gtk.main_quit)
    gtk.main()

if __name__ == '__main__':
    main()
