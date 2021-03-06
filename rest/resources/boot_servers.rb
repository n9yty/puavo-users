
module PuavoRest
class BootServer < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoHostname, :hostname
  ldap_map(:puavoSchool, :school_dns) { |s| s }
  ldap_map(:puavoTag, :tags){ |v| Array(v) }
  ldap_map :puavoConf, :puavoconf, LdapConverters::PuavoConfObj
  ldap_map(:puavoDeviceImage, :preferred_image) do |img|
    img = Array(img).first
    if not img.to_s.strip.empty?
      img.strip
    end
  end
  ldap_map :puavoDeviceCurrentImage, :current_image, LdapConverters::SingleValue
  ldap_map :puavoDeviceAvailableImage, :available_images, LdapConverters::ArrayValue
  ldap_map :puavoImageSeriesSourceURL, :image_series_source_urls, LdapConverters::ArrayValue

  # Return true if the current puavo-rest server is running on a boot server
  def self.running_on?
    !!CONFIG["bootserver"]
  end

  def self.current_dn
    return if not running_on?

    if ENV["RACK_ENV"] == "test"
      if !PuavoRest.test_boot_server_dn.nil?
        return PuavoRest.test_boot_server_dn
      end
    end

    PUAVO_ETC.ldap_dn
  end

  def self.current!
    BootServer.by_dn!(current_dn)
  end

  # return current bootserver image or nil
  def self.current_image
    if running_on?
      current!.preferred_image
    end
  end

  def self.ldap_base
    "ou=Servers,ou=Hosts,#{ organisation["base"] }"
  end

  # Bootservers are saved to same ldap branch as ltsp servers so we must filter
  # with type too
  def self.base_filter
    "(puavoDeviceType=bootserver)"
  end

  def self.by_hostname(hostname)
    by_attr(:hostname, hostname)
  end

  def self.by_hostname!(hostname)
    by_attr!(:hostname, hostname)
  end

  def puavoconf
    (organisation.puavoconf || {}) \
      .merge(get_own(:puavoconf) || {})
  end

  def schools
    self["school_dns"].map do |school_dn|
      School.by_dn(school_dn)
    end
  end

  # Cached organisation query
  def organisation
    @organisation ||= Organisation.by_dn(self.class.organisation["base"])
  end

  def image_series_source_urls
    if get_own(:image_series_source_urls).empty?
      organisation.image_series_source_urls
    else
      get_own(:image_series_source_urls)
    end
  end

end

class BootServers < PuavoSinatra

  get "/v3/boot_servers" do
    auth :basic_auth, :server_auth
    json BootServer.all
  end

  get "/v3/boot_servers/:hostname" do
    auth :basic_auth, :server_auth
    json BootServer.by_hostname!(params["hostname"])
  end

  post "/v3/boot_servers/:hostname" do
    auth :basic_auth, :kerberos
    server = BootServer.by_hostname!(params["hostname"])
    server.update!(json_params)
    server.save!
    json server
  end

  get "/v3/boot_servers/:hostname/wireless_printer_queues" do
    auth :basic_auth, :server_auth

    server = BootServer.by_hostname!(params["hostname"])
    printer_queues = []
    server.schools.each do |school|
      printer_queues += school.wireless_printer_queues
    end
    json printer_queues.uniq { |printer_queue| printer_queue.name }
  end

end
end
