namespace :db do
  desc "scan for possible required indexes"
  task :show_me_some_indexes => :environment do
    
    model_names = []
    Dir.chdir(File.join(Rails.root, "app/models")) do 
      model_names = Dir["**/*.rb"]
    end
    
    model_classes = []
    model_names.each do |model_name|
      class_name = model_name.sub(/\.rb$/,'').camelize
      klass = class_name.split('::').inject(Object){ |klass,part| klass.const_get(part) }
      if klass < ActiveRecord::Base && !klass.abstract_class?
        model_classes << klass
      end
    end
    puts "Found #{model_classes.size} Models"
    
    @indexes_required = Hash.new([])
    
    model_classes.each do |class_name|
    #  puts "-" * 60
    #  puts "Inspecting #{class_name.to_s}"
      
      foreign_keys = []
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
    
    @indexes_required.each_pair do |table_name, foreign_keys|
   
      unless foreign_keys.blank?
        existing_indexes = ActiveRecord::Base.connection.indexes(table_name.to_sym).collect(&:columns).flatten
        puts "Table '#{table_name}' => #{(foreign_keys.uniq - existing_indexes).to_sentence}"
      end
    end
  end
end