#! /usr/bin/env ruby
#
# Converts a GEDCOM file into a DOT file, with pruning options
#
# Originally written Oct 8, 2007 by Stonewall Ballard
# Modified by December 2014 by Arnold P. Siboro
#
# Related sources:
#
# GEDCOM to Graphviz
# http://stoney.sb.org/wordpress/2007/10/gedcom-to-graphviz/
# 
# Matthew Gray's blog entry 
# http://www.mkgray.com:8000/blog/Personal/Family-Tree-Graphing.html
#
# Based on examples from gedcom-ruby <http://gedcom-ruby.sourceforge.net/>, which is required for operation.
#
# License: Creative Commons Attribution 3.0 Unported <http://creativecommons.org/licenses/by/3.0/>

require 'gedcom'
#require './gedcom-ruby/lib/gedcom.rb'
require 'getoptlong'

$HELP_TEXT = <<-HELPEND
#{$0} convertes a GEDCOM file into a Graphviz DOT file
Command: #{$0} opts gedfile
dot file is written to stdout
Options:
  --root Fxxx|Ixxx    Sets root Family or Individual to argument and prunes away unrelated people
  --children          Shows children in every related family if root is set
  --blood             Shows only blood relatives of root
HELPEND

class Person
	attr_accessor :id
	attr_accessor :name
	# the family of which this person is a parent
	attr_accessor :parent_family
	# the family of which this person is a child
	attr_accessor :child_family
	attr_accessor :marked
	
	def initialize( id = nil, name = nil, parent_family = nil, child_family = nil, marked = nil )
		@id, @name, @parent_family, @child_family, @marked = id, name, parent_family, child_family, marked
	end
end

class Family
	attr_accessor :id
	attr_accessor :parents
	attr_accessor :children
	attr_accessor :marked

	def initialize( id = nil, parents = [], children = [], marked = nil )
		@id, @parents, @children, @marked = id, parents, children, marked
	end
end

class DotMaker < GEDCOM::Parser
	attr_reader :individuals
	attr_reader :families

	def initialize( root_entity, show_children, show_blood, use_initials)
		@root_entity, @show_children, @show_blood = root_entity, show_children, show_blood, use_initials

		super()

		@current_person = nil
		@current_family = nil
		@people = {}
		@families = {}
# root_entity is set as argument to this program, either an individual (I...) or family (F...)
# here root_is_family is set to true when the argument starts with an F
		@root_is_family = @root_entity =~ /\AF/

# explanation about setPreHandler and setPostHandler can be found here:
# https://github.com/binary011010/gedcom-ruby/blob/master/README
		setPreHandler	 [ "INDI" ], method( :start_person )
		setPreHandler	 [ "INDI", "NAME" ], method( :register_name )
		setPreHandler	 [ "INDI", "FAMC" ], method( :register_parent_family )
		setPreHandler	 [ "INDI", "FAMS" ], method( :register_child_family )
		setPostHandler [ "INDI" ], method( :end_person )

		setPreHandler	 [ "FAM" ], method( :start_family )
		setPreHandler	 [ "FAM", "HUSB" ], method( :register_parent )
		setPreHandler	 [ "FAM", "WIFE" ], method( :register_parent )
		setPreHandler	 [ "FAM", "CHIL" ], method( :register_child )
		setPostHandler [ "FAM" ], method( :end_family )

	end

	def cid( idv )
		id = idv.delete("@")
		return nil if id == "I-1"
		id
	end

	def start_person( data, state, parm )
# set current person to the ID of the person (without the "@")
		@current_person = Person.new cid( data )
	end

	def register_name( data, state, parm )
		@current_person.name = data
	end
	
	def register_parent_family( data, state, parm )
		@current_person.parent_family = cid data
	end

	def register_child_family( data, state, parm )
		@current_person.child_family = cid data
	end

	def end_person( data, state, parm )
		@people[@current_person.id] = @current_person
# mark person if person is not root entity
		@current_person.marked = @root_entity == nil
		#if @current_person.marked then $stderr.puts "person marked (root entity): #{@root_entity} #{@current_person.name}" end
		@current_person = nil
	end

	def start_family( data, state, parm )
		@current_family = Family.new cid( data )
	end

	def register_parent( data, state, parm )
		# a parent may be missing (@I-1@)
		d = cid data
		@current_family.parents.push d if d
	end
	
	def register_child( data, state, parm )
		@current_family.children.push cid( data )
	end
	
	def end_family( data, state, parm )
		@families[@current_family.id] = @current_family
		@current_family.marked = @root_entity == nil
		@current_family = nil
	end
	
	def mark_parents(person)
		unless person.marked
			person.marked = true
			fid = person.parent_family
			if fid
				f = @families[fid]
				f.marked = true
				f.parents.each { |p| mark_parents( @people[p] ) }
				if @show_children
					f.children.each { |c| @people[c].marked = true }
				elsif @show_blood
					f.children.each { |c| mark_children @people[c] }
				end
			end
		end
	end
	
	def mark_children(person)
		unless person.marked
			person.marked = true
			fid = person.child_family
			#if fid then $stderr.puts "person.child_family for #{person.name}: #{fid}" end
			if fid
				f = @families[fid]
				f.marked = true
				f.children.each { |c| mark_children( @people[c] ) }
			end
		end
	end
	
	def mark_family(family)
		family.marked = true
		family.parents.each { |p| mark_parents( @people[p] ) }
		family.children.each { |c| mark_children( @people[c] ) }
	end
	
	def trim_tree
		# mark every individual and family appropriately related to the root family or person
		if @root_entity
			if @root_is_family
				root_family = @families[@root_entity]
				unless root_family
					$stderr.puts "No family id = #{@root_entity} found"
					exit(0)
				end
				mark_family root_family
			else
				root_person = @people[@root_entity]
				unless root_person
					$stderr.puts "No person id = #{@root_entity} found"
					exit(0)
				end
				mark_parents root_person
				root_person.marked = false
				mark_children root_person
			end
		end
	end

# Create a compact name to be used on node's label
	def createlabelname(name)		

		splitname=name.split("/")
		for i in 1..splitname.length do
# If the name is within brackets, then actual name of the person is unknown
			if(splitname[i-1] =~ /^\(.+\)/) 
				splitname[i-1] = "(....)\n" 
			end
		end	
			
		name=splitname.join("")

# Initialize long name
		splitname=name.split(" ")
		for i in 1..splitname.length do
# If there are more than 2 names, and this is not 1st name or last name, and it is not already initialized, and this is not 2nd name while the first name is a title such as "Ompu"
			if(splitname.length>2 && i != 1 && i != splitname.length && !(i==2 && (splitname[0].strip=="Ompu" || splitname[0].strip=="O." || splitname[0].strip=="Amani"|| splitname[0].strip=="A." || splitname[0].strip=="Aman" || splitname[0].strip=="Datu" || splitname[0].strip=="Nai" || splitname[0].strip=="Apa")) )
					splitname[i-1] = splitname[i-1][0,1].capitalize + "."
			end	
		end

# Put each name in new line to shorthen it
#		name.gsub!(" ","\n")

		for i in 1..splitname.length do
# If this name is not an initial (ended by "."), or if it is an initial but before a non-initial
			if(splitname[i-1] && splitname[i])
			if(splitname[i-1][-1,1] != "." || (splitname[i-1][-1,1] == "." && splitname[i][-1,1] != "."))
				splitname[i-1]=splitname[i-1] + "\n"
			end
			end
		end


		name=splitname.join("")

		label= name	
		return label
	end

	
	def report
		$stderr.puts "Found #{@people.length} people and #{@families.length} families"
	end
	
	def export
		$stderr.puts "Exporting..."
		puts "digraph familyTree {"
		# the format of all nodes
		puts "    node [width=0.1 height=0.1 fixedsize=true label=\"\"]"
		puts "    edge [arrowhead=none]"
		# families are circles
		puts "    node [shape=circle]"
		puts "    fontsize=6"
		if @root_is_family
			# color the root family red
			puts "    #{@root_entity} [style=filled fillcolor=red]"
		end
		# the format of the regular family nodes
		#puts "    node [style=filled fillcolor=black]"
		# list all the family nodes so that they take on the above format
		ids_on_line = 0

		$stderr.puts "Write node definition of all marked families ... "
		print "    "
		@families.each_value do |fam|
# if family is marked, then write node definition
			next unless fam.marked
			print "#{fam.id}; "
 			#print "#{fam.id} [ label=\"" + "#{fam.id}" + "\" ];"
			#if fam.parents[0] then print "#{fam.id} [ label=""" + "#{fam.parents[0]}" + """ ];" else print "#{fam.id} ;" end
			print "\n    "
			ids_on_line += 1
			if ids_on_line >= 10
				print "\n    "
				ids_on_line = 0;
			end
		end

		counter=0;
		$stderr.puts "Write node definition of all marked persons..."
		print "    "
		@people.each_value do |person|
			counter=counter+1;
# if person is marked, then write node definition
			next unless person.marked
			#print "#{person.id}; "
 			#print "#{person.id} [ label=""" + "#{person.parents[0]}" + """ ];"

				labelname=createlabelname(person.name)

			#$stderr.puts "#{counter}: "+"#{labelname}"
			print "#{person.id} [ label=\"" + "#{labelname}" + "\" shape=box fontsize=6 color=white style=solid];"
			print "\n    "
			ids_on_line += 1
			if ids_on_line >= 10
				print "\n    "
				ids_on_line = 0;
			end
		end

		print "\n" unless ids_on_line == 0
		# people are squares
		puts "    node [shape=box]"
		if @root_entity && !@root_is_family #never executed?
			# format the root person node specially
			puts "    #{@root_entity} [style=filled fillcolor=red]"
		end

		$stderr.puts "Connecting all marked persons to their parent family..."
		# the format of the person nodes applies to all unseen (so far) nodes
		# note that there's no "empty" style, but just saying [style] seems to return it to the default
		# puts "    node [style]"
		# emit all the person -> family links
		@people.each_value do |p|
			next unless p.marked
			puts "    #{p.id} -> #{p.parent_family}" if p.parent_family
		end

		#emit all the family -> parent links

# connect families, and shows persons connected by marriage
		$stderr.puts "Connecting couples to their family..."
		@families.each_value do |f|
# if family is marked, then write connection
			next unless f.marked
			par = f.parents
			# this prunes parents that are not blood related to root entity, i.e., spouses are pruned
			#par = par.find_all { |p| @people[p].marked }

			# so, because we want spouse to be included too, do this
			nonbloodrelated = par.find_all { |p| !@people[p].marked }
			if nonbloodrelated.length==1 then # it is impossible for both parents to be non-blood related though
				nonbloodrelatedperson=@people[nonbloodrelated[0]]
				#$stderr.puts "#{nonbloodrelated[0]}: #{nonbloodrelatedperson.name}" 

				labelname=createlabelname(nonbloodrelatedperson.name)
			print "#{nonbloodrelatedperson.id} [ label=\"" + "#{labelname}" + "\" shape=box fontsize=6 color=white style=solid];"


end
			unless par.empty?
				pars = par.join('; ')
				pars = "{#{pars};}" if par.length > 1
				puts "    #{f.id} -> #{pars}"
				#$stderr.puts "#{f.id}" + " " + pars
			end
		end
		puts "}\n"
	end
end

# main program
opts = GetoptLong.new(
  ["--root", "-r", GetoptLong::REQUIRED_ARGUMENT],
  ["--children", "-c", GetoptLong::NO_ARGUMENT],
	["--blood", "-b", GetoptLong::NO_ARGUMENT],
	["--initials", "-i", GetoptLong::NO_ARGUMENT],
  ["--help", "-h", GetoptLong::NO_ARGUMENT]
)

root_entity = nil
show_children = nil
show_blood = nil
use_initials= nil

opts.each do |opt, arg|
	case opt
	when "--root"
		root_entity = arg.upcase
		unless root_entity =~ /\A(F|I)\d+\z/
			$stderr.puts "--root argument must be F or I followed by digits, like F123 or I4"
			exit(1)
		end
	when "--children"
		show_children = true
	when "--blood"
		show_blood = true
	when "--initials"
		use_initials = true
	when "--help"
		puts $HELP_TEXT
		exit(0)
	end
	if show_children && show_blood
		puts "Only one of --children and --blood can be specified"
		exit(1)
	end
end

if ARGV.length < 1
	$stderr.puts "Please specify the name of a GEDCOM file."
	exit(1)
end

parser = DotMaker.new( root_entity, show_children, show_blood, use_initials)
parser.parse ARGV[0]

#parser.report

# remove all the people unrelated to the root person or family if set
parser.trim_tree if root_entity

# export the dot file
parser.export
parser.report

