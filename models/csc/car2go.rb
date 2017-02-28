module Car2Go
  class Car < Car
    def initialize(hsh)
      super(hsh)
      crds = @data["coordinates"]
      @location = Geokit::LatLng.new(crds[1],crds[0])
      @data["fuelType"] = "PE10" # only applies if non-electro
    end

    def is_electro?
      @data["engineType"] == "ED"
    end

    def name
      @data["name"]
    end

    def needs_fuelling?
      @data["fuel"] <= 25
    end

    def is_charging?
      !!@data["charging"]
    end

    def address_line
      @data["address"]
    end

    def marker_icon
      "/images/marker_car2go_car.svg"
    end

    def vin
      @data["vin"]
    end

    def latlng
      [location.lat, location.lng].join(",")
    end

    def reserve_url
      "car2go://car2go.com/vehicle/%s?latlng=%s" % [ vin, latlng ]
    end

    def fuel_in_percent
      @data["fuel"]
    end

    def license_plate
      @data["name"]
    end

    def cleanliness
      @data["interior"] == "GOOD" ? "2/2" : "2/1"
    end
  end

  class PetrolFS < PetrolFS
    def initialize(hsh)
      org, addr = hsh["name"].split(/,/).map(&:strip)
      hsh["latitude"]     = hsh["coordinates"][1]
      hsh["longitude"]    = hsh["coordinates"][0]
      hsh["name"]         = org
      hsh["address"]      = [addr]
      hsh["organisation"] = org
      super(hsh)
    end

    def marker_icon
      "/images/station/c2g/petrol/marker.svg"
    end
  end

  class ElectroFS < ElectroFS
    def initialize(hsh)
      hsh["latitude"]     = hsh["coordinates"][1]
      hsh["longitude"]    = hsh["coordinates"][0]
      hsh["address"]      = [hsh["name"]]
      hsh["name"]         = "-"
      super(hsh)
    end

    def marker_icon
      "/images/station/c2g/electro/"+(is_crowded? ? "crowded" : "empty")+".svg"
    end

    def capacity_info
      used,total = ["usedCapacity","totalCapacity"].map{|a|@data[a]}.map(&:to_i)
      { :free => total - used, :total => total }
    end
  end


  class City < City
    def self.all
      Curlobj.
        car2go_data_for("https://www.car2go.com/api/v2.1/locations?"+
                        "oauth_consumer_key=#{ENV['CAR2GO_CONSUMER_KEY']}"+
                        "&format=json")["location"].map do |hsh|
        Car2Go::City.new(hsh)
      end
    end

    def initialize(hsh)
      hsh["locationName"] = hsh["id"] if hsh["id"]
      super(hsh)
      loc = @data["mapSection"]["center"] rescue {}
      @location = Geokit::LatLng.new(loc["latitude"], loc["longitude"])
    end

    def name
      "%s, %s" % [ @data["locationName"], @data["countryCode"] ]
    end

    def id
      data["locationName"]
    end

    def car_details
      {}.tap do |resp|
        resp[:cars] = Curlobj.
          car2go_data_for("https://www.car2go.com/api/v2.1/vehicles"+
                          "?oauth_consumer_key=#{ENV['CAR2GO_CONSUMER_KEY']}"+
                          "&format=json&loc=" +
                          CGI::escape(id))["placemarks"].map do |hsh|
          Car2Go::Car.new(hsh)
        end

        resp[:electro_stations] = Curlobj.
          car2go_data_for("https://www.car2go.com/api/v2.1/parkingspots"+
                          "?oauth_consumer_key=#{ENV['CAR2GO_CONSUMER_KEY']}"+
                          "&format=json&loc=" +
                          CGI::escape(id))["placemarks"].
          select { |hsh| hsh["chargingPole"] }.
          map do |hsh|
          Car2Go::ElectroFS.new(hsh)
        end

        resp[:petrol_stations] = Curlobj.
          car2go_data_for("https://www.car2go.com/api/v2.1/gasstations"+
                          "?oauth_consumer_key=#{ENV['CAR2GO_CONSUMER_KEY']}"+
                          "&format=json&loc=" +
                          CGI::escape(id))["placemarks"].map do |hsh|
          Car2Go::PetrolFS.new(hsh)
        end
      end
    rescue Exception => e
      puts "Exception for City: #{id} / #{name}"
      puts e
      EmptyCarDetails
    end
  end
end
CscProviders.register("ctg", "Car2Go", Car2Go::City)
