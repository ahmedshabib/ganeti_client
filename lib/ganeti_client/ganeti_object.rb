module Ganeti
    class GanetiObject
    
        attr_accessor :json_object

        def initialize(json = {})
            new_json = {}
            json.each { |key, value| new_json[key.gsub('.', '_')] = value }
                            
            self.json_object = new_json
            
            new_json.each { |attr_name, attr_value| self.class.send(:define_method, attr_name.to_sym){ return attr_value } }
        end

        def to_json
            return self.json_object
        end
    end
end
