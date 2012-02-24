#################################################################################
# Copyright (C) 2011, 2012 - Mariano Spadaccini    mariano@marianospadaccini.it	#
#                                                                               #
# This file is part of pi                                                       #
#                                                                               #
#  pi is free software; you can redistribute it and/or modify                   #
#  it under the terms of the GNU General Public License as published by         #
#  the Free Software Foundation; either version 2 of the License, or            #
#  (at your option) any later version.                                          #
#                                                                               #
#  pi is distributed in the hope that it will be useful,                        #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of               #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
#  GNU General Public License for more details.                                 #
#                                                                               #
#  You should have received a copy of the GNU General Public License            #
#  along with Foobar; if not, write to the Free Software                        #
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA   #
#################################################################################

sqlite3 pi.sqlite
CREATE TABLE client (clientIpPort varchar(15), last datetime, primary key (clientIpPort));
CREATE TABLE pi (i int8, wait smallint, primary key (i));
.exit
