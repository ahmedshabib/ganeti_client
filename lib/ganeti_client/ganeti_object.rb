module Ganeti
    class GanetiObject
    
        attr_accessor :json_object

        def initialize(json = {})
            self.json_object = json
            
            json.each { |attr_name, attr_value| self.class.send(:define_method, attr_name.to_sym){ return attr_value } }
        end

        def to_json
            return self.json_object
        end
    end
end
