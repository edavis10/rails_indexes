def check_for_indexes
  model_names = []
  Dir.chdir(Rails.root) do 
    model_names = Dir["**/app/models/*.rb"].collect {|filename| filename.split('/').last }
  end
  
  model_classes = []
  model_names.each do |model_name|
    class_name = model_name.sub(/\.rb$/,'').camelize
    begin
      klass = class_name.split('::').inject(Object){ |klass,part| klass.const_get(part) }
      if klass < ActiveRecord::Base && !klass.abstract_class?
        model_classes << klass
      end
    rescue
      # No-op
    end
  end
  puts "Found #{model_classes.size} Models"
  
  @indexes_required = Hash.new([])
  
  model_classes.each do |class_name|
    
    foreign_keys = []
    
    # check if this is an STI child instance
    if class_name.base_class.name != class_name.name
      # add the inharitance column on the parent table
      @indexes_required[class_name.base_class.table_name] += [class_name.base_class.inheritance_column]
    end
    
    class_name.reflections.each_pair do |reflection_name, reflection_options|
      case reflection_options.macro
      when :belongs_to
        # polymorphic?
        if reflection_options.options.has_key?(:polymorphic) && (reflection_options.options[:polymorphic] == true)
          @indexes_required[class_name.table_name.to_s] += ["#{reflection_options.name.to_s}_type", "#{reflection_options.name.to_s}_id"]
        else
          @indexes_required[class_name.table_name.to_s] += [reflection_options.primary_key_name]
        end
      when :has_and_belongs_to_many
        @indexes_required[reflection_options.options[:join_table]] += [reflection_options.options[:association_foreign_key], reflection_options.options[:foreign_key]]
      else
        #nothing
      end
    end
  end

  @missing_indexes = {}
  @indexes_required.each do |table_name, foreign_keys|
    
    unless foreign_keys.blank?
      existing_indexes = ActiveRecord::Base.connection.indexes(table_name.to_sym).collect(&:columns).flatten
      keys_to_add = foreign_keys.uniq - existing_indexes
      @missing_indexes[table_name] = keys_to_add unless keys_to_add.empty?
    end
  end
  @missing_indexes
end

namespace :db do
  desc "scan for possible required indexes"
  task :show_me_some_indexes => :environment do
    
    check_for_indexes.each do |table_name, keys_to_add|
      puts "Table '#{table_name}' => #{keys_to_add.to_sentence}"
    end
  end
  
  task :show_me_a_migration => :environment do
    missing_indexes = check_for_indexes

    unless missing_indexes.empty?
      add = []
      remove = []
      missing_indexes.each do |table_name, keys_to_add|
        keys_to_add.each do |key|
          next if key.blank?
          add << "add_index :#{table_name}, :#{key}"
          remove << "remove_index :#{table_name}, :#{key}"
        end
      end
      
      migration = <<EOM
class AddMissingIndexes < ActiveRecord::Migration
  def self.up
    #{add.join("\n    ")}
  end
  
  def self.down
    #{remove.join("\n    ")}
  end
end
EOM

      puts "## Drop this into a file in db/migrate ##"
      puts migration
    end
  end
end
