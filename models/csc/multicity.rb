module Multicity
  class Car < Car
    def initialize(hsh)
      super(hsh)
      @vehicle  = @data["value"]["vehicle"]
      loc       = @data["location"]
      @location = Geokit::LatLng.new(loc["latitude"], loc["longitude"])
    end

    def is_electro?
      @vehicle["powerType"] == "electric"
    end

    def name
      "%s (%s)" % [@vehicle["license"], @vehicle["name"][0..15].strip]
    end

    def needs_fuelling?
      @vehicle["fillLevel"] < 50
    end

    def is_charging?
      false
    end

    def image_url
      "https://www.multicity-carsharing.de/wp-content/plugins/" +
        "multicity_map_v2/img/image_" + (is_electro? ? "multicity" : "c1") +
        ".jpg"
    end

    def marker_icon
      "/images/marker_mc_" + (is_electro? ? "electro" : "therm") + ".png"
    end

    def reserve_url
      "multicity://bookvehicle?rentalobjectid=" + @vehicle["rentalObjectID"]
    end

    def fuel_in_percent
      @vehicle["fillLevel"]
    end
  end

  class PetrolFS < PetrolFS
    def initialize(hsh)
      loc = hsh["location"]
      hsh["latitude"]     = loc["coordinates"][1]
      hsh["longitude"]    = loc["coordinates"][0]

      hsh["name"]         = hsh["value"]["name"]
      hsh["address"]      = ["-"]
      hsh["organisation"] = ""
      super(hsh)
    end

    def marker_icon
      "/images/marker_mc_petrolstation.png"
    end
  end

  class ElectroFS < ElectroFS
    def initialize(hsh)
      hsh["latitude"]  = hsh["lat"]
      hsh["longitude"] = hsh["lng"]

      @mrkinfo    = hsh["hal2option"]["markerInfo"]
      hsh["name"] = @mrkinfo["name"]

      addr = @mrkinfo["address"]
      hsh["address"] = [ addr["streetName"] + addr["houseNumber"],
                         addr["postalCode"] + " " + addr["city"]]
      hsh["organisation"] = "RWE"
      super(hsh)
    end

    def is_full?
      capacity_info[:free] == 0
    end

    def is_crowded?
      cpi = capacity_info
      cpi[:free] != cpi[:total]
    end

    def marker_icon
      "/images/marker_mc_ladesaeule" + (is_crowded? ? "_crowded" : "") + ".png"
    end

    def capacity_info
      { :free => @mrkinfo["free"].to_i, :total => @mrkinfo["capacity"].to_i }
    end
  end

  class City < City
    def self.all
      [Multicity::City.new("name" => "Berlin, Deutschland", "id" => "403037",
                           "lat" => 52.5166667, "lng" => 13.4)]
    end

    def initialize(hsh)
      super(hsh)
      @location = Geokit::LatLng.new(hsh["lat"], hsh["lng"])
    end

    def name
      data["name"]
    end

    def id
      data["id"]
    end

    def car_details
      {}.tap do |resp|
        resp[:cars] = Curlobj.
          multicity_data_for("https://www.multicity-carsharing.de"+
                             "/_denker-mc.php").map do |hsh|
          Multicity::Car.new(hsh)
        end

        opts = {
          :post => true,
          :data => {
            :name => "url",
            :value => ("/gasstations?lat=#{@location.lat}&lon="+
                       "#{@location.lng}&dist=50000")
          }
        }
        resp[:petrol_stations] = Curlobj.
          multicity_data_for("https://www.multicity-carsharing.de/"+
                             "_denker-mob.php",opts).map do |hsh|
          Multicity::PetrolFS.new(hsh)
        end

        resp[:electro_stations] = Curlobj.
          multicity_data_for("https://www.multicity-carsharing.de/rwe_utf8/"+
                             "json.php?max=10000")["marker"].map do |hsh|
          Multicity::ElectroFS.new(hsh)
        end.reject { |a| a.is_full? }
      end
    end
  end
end