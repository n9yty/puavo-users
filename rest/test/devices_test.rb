require 'openssl'
require_relative "./helper"

describe PuavoRest::Devices do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoSchoolHomePageURL => "schoolhomepagefordevice.example",
      :puavoAllowGuest => true,
      :puavoAutomaticImageUpdates => true,
      :puavoImageSeriesSourceURL => ["https://foobar.opinsys.fi/schoolpref.json"],
      :puavoLocale => "fi_FI.UTF-8",
      :puavoTag => ["schooltag"],
      :puavoConf => '{
        "puavo.admin.personally_administered": true,
        "puavo.autopilot.enabled": false,
        "puavo.desktop.vendor.logo": "/usr/share/opinsys-art/logo.png",
        "puavo.login.external.enabled": false
      }',
      :puavoMountpoint => [ '{"fs":"nfs3","path":"10.0.0.3/share","mountpoint":"/home/school/share","options":"-o r"}',
                            '{"fs":"nfs4","path":"10.5.5.3/share","mountpoint":"/home/school/public","options":"-o r"}' ]
    )

    @role = Role.new
    @role.displayName = "Some role"
    @role.puavoSchool = @school.dn
    @role.save!

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :puavoLocale => "en_US.UTF-8",
      :mail => "bob@example.com",
      :puavoSchool => @school.dn,
      :role_ids => [@role.puavoId]
    )
    @user.save!

    @school_without_fallback_value = School.create(
      :cn => "gryffindor2",
      :displayName => "Gryffindor2"
    )
    @server1 = create_server(
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => @school.dn,
      :puavoDeviceType => "ltspserver"
    )
    @bootserver = create_server(
      :puavoHostname => "bootserver",
      :macAddress => "bc:5f:f4:56:59:72",
      :puavoDeviceType => "bootserver"
    )
    PuavoRest.test_boot_server_dn = @bootserver.dn.to_s

    @printer = Printer.create(
      :printerDescription => "printer1",
      :printerLocation => "school2",
      :printerMakeAndModel => "foo",
      :printerType => "1234",
      :printerURI => "socket://baz",
      :puavoServer => @server1.dn
    )

    @school.add_wireless_printer(@printer)

    # School#reload for some reason clears some attributes. Workaround it for
    # now.
    @school = School.find(@school.dn)

    test_organisation = LdapOrganisation.first # TODO: fetch by name
    test_organisation.puavoAllowGuest = "FALSE"
    test_organisation.puavoAutomaticImageUpdates = "FALSE"
    test_organisation.puavoPersonalDevice = "FALSE"

    test_organisation.puavoConf = '{
      "puavo.desktop.vendor.logo": "/usr/share/puavo-art/puavo-os_logo-white.svg",
      "puavo.l10n.locale": "ja_JP.eucJP",
      "puavo.login.external.enabled": true,
      "puavo.time.timezone": "Europe/Tallinn"
    }'

    test_organisation.save!
  end

  describe "device information" do
    before(:each) do
      @_athin = create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoDeviceImage => "customimage",
        :puavoSchool => @school.dn,
        :puavoPersonalDevice => false,
        :puavoDefaultPrinter => "defaultprinter",
        :puavoImageSeriesSourceURL => "https://foobar.opinsys.fi/images.json",
        :puavoAllowGuest => false,
        :puavoAutomaticImageUpdates => false,
        :puavoPersonallyAdministered => true,
        :primary_user_uid => 'bob',
        :puavoPrinterDeviceURI => "usb:/dev/usb/lp1",
        :puavoDeviceDefaultAudioSource => "alsa_input.pci-0000_00_1b.0.analog-stereo",
        :puavoDeviceDefaultAudioSink => "alsa_output.pci-0000_00_1b.0.analog-stereo",
        :puavoTag => ["tag1", "tag2"],
        :puavoConf => '{
          "puavo.autopilot.enabled": true,
          "puavo.guestlogin.enabled": true,
          "puavo.xbacklight.brightness": 80
        }',
      )
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoAllowGuest = "TRUE"
      test_organisation.puavoPersonalDevice = "TRUE"
      test_organisation.puavoImageSeriesSourceURL = nil
      test_organisation.save!
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has image series source url" do
      assert_equal "https://foobar.opinsys.fi/images.json", @data["image_series_source_urls"].first
    end

    it "has mac address" do
      assert_equal "bf:9a:8c:1b:e0:6a", @data["mac_address"]
    end

    it "has preferred server" do
      assert_equal @server1.dn, @data["preferred_server"]
    end

    it "has preferred image" do
      assert_equal "customimage", @data["preferred_image"]
    end

    it "has allow guest" do
      assert_equal false, @data["allow_guest"]
    end

    it "has automatic image updates" do
      assert_equal false, @data["automatic_image_updates"]
    end

    it "has personally administered" do
      assert_equal true, @data["personally_administered"]
    end

    it "has primary user" do
      assert_equal "bob", @data["primary_user"]
    end

    it "has personal device" do
      assert_equal false, @data["personal_device"]
    end

    it "has printer uri" do
      assert_equal "usb:/dev/usb/lp1", @data["printer_device_uri"]
    end

    it "has default printer" do
      assert_equal "defaultprinter", @data["default_printer_name"]
    end

    it "has default input audio device" do
      assert_equal "alsa_input.pci-0000_00_1b.0.analog-stereo", @data["default_audio_source"]
    end

    it "has default sink audio device" do
      assert_equal "alsa_output.pci-0000_00_1b.0.analog-stereo", @data["default_audio_sink"]
    end

    it "has preferred language" do
      assert_equal "fi", @data["preferred_language"]
    end

    it "has locale" do
      assert_equal "fi_FI.UTF-8", @data["locale"]
    end
    it "has homepage from school" do
      assert_equal "schoolhomepagefordevice.example", @data["homepage"]
    end

    it "has tags" do
      assert @data["tags"], "has tags"
      assert @data["tags"].include?("tag1"), "has tag1"
      assert @data["tags"].include?("tag2"), "has tag2"
      assert @data["tags"].include?("schooltag"), "has schooltag"
    end

    it "has conf with mapped puavo-conf values" do
      conf = @data['conf']

      # We test that some settings that have specific attributes in ldap
      # are mapped to puavo-conf key/value-pairs.
      assert conf.kind_of?(Hash), 'device data has "conf" that is a Hash'
      assert_equal 'alsa_output.pci-0000_00_1b.0.analog-stereo',
	           conf['puavo.audio.pa.default_sink']
      assert_equal 'false', conf['puavo.image.automatic_updates']
      assert_equal 'customimage', conf['puavo.image.preferred']
      assert_equal 'defaultprinter', conf['puavo.printing.default_printer']
      assert_equal 'schoolhomepagefordevice.example',
	           conf['puavo.www.homepage']
    end

    it "has conf with explicit and merged puavo-conf values" do
      conf = @data['conf']

      assert conf.kind_of?(Hash), 'device data has "conf" that is a Hash'
      assert_equal 'true', conf['puavo.admin.personally_administered']
      assert_equal 'true', conf['puavo.autopilot.enabled']
      assert_equal'/usr/share/opinsys-art/logo.png',
                   conf['puavo.desktop.vendor.logo']
      assert_equal 'true', conf['puavo.guestlogin.enabled']
      assert_equal 'ja_JP.eucJP', conf['puavo.l10n.locale']
      assert_equal 'false', conf['puavo.login.external.enabled']
      assert_equal 'Europe/Tallinn', conf['puavo.time.timezone']
      assert_equal '80', conf['puavo.xbacklight.brightness']
    end

    it "has timezone" do
      assert_equal "Europe/Helsinki", @data["timezone"]
    end

    it "has keyboard layout" do
      assert_equal "en", @data["keyboard_layout"]
    end

    it "has kehboard variant" do
      assert_equal "US", @data["keyboard_variant"]
    end

    it "it prefers language from the school" do
      @school.puavoLocale = "sv_FI.UTF-8"
      @school.save!
      get "/v3/devices/athin"
      assert_200
      data = JSON.parse last_response.body

      assert_equal "sv", data["preferred_language"]
      assert_equal "sv_FI.UTF-8", data["locale"]
    end

  end

  describe "device information with school fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,
        :puavoMountpoint => [ '{"fs":"nfs4","path":"10.0.0.2/share","mountpoint":"/home/device/share","options":"-o rw"}',
                              '{"fs":"nfs3","path":"10.4.4.4/share","mountpoint":"/home/school/share","options":"-o r"}' ]
      )
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has image series source url" do
      assert_equal "https://foobar.opinsys.fi/schoolpref.json", @data["image_series_source_urls"].first
    end

    it "has preferred image" do
      assert_equal "schoolprefimage", @data["preferred_image"]
    end

    it "has allow guest" do
      assert_equal true, @data["allow_guest"]
    end

    it "has automatic image updates" do
      assert_equal true, @data["automatic_image_updates"]
    end

    it "has personal device" do
      assert_equal true, @data["personal_device"]
    end

    it "has preferred language" do
      assert @data["preferred_language"]
      assert_equal "fi", @data["preferred_language"]
    end

    it "has mountpoint" do
      correct_mountpoints = [ { "fs" => "nfs4",
                                "path" => "10.0.0.2/share",
                                "mountpoint" => "/home/device/share",
                                "options" => "-o rw" },
                              { "fs" => "nfs3",
                                "path" => "10.4.4.4/share",
                                "mountpoint" => "/home/school/share",
                                "options" => "-o r" },
                              { "fs" => "nfs4",
                                "path" => "10.5.5.3/share",
                                "mountpoint" => "/home/school/public",
                                "options" => "-o r" } ].sort{ |a,b| a.to_s <=> b.to_s }
      data_mountpoints = @data["mountpoints"].sort{ |a,b| a.to_s <=> b.to_s }
      assert_equal( correct_mountpoints,
                    data_mountpoints )
    end
  end

  describe "device information with organisation fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has image series source url" do
      assert_equal "https://foobar.opinsys.fi/organisationpref.json", @data["image_series_source_urls"].first
    end

    it "has allow guest" do
      assert_equal false, @data["allow_guest"]
    end

    it "has automatic image updates" do
      assert_equal false, @data["automatic_image_updates"]
    end

    it "has personal device" do
      assert_equal false, @data["personal_device"]
    end

    it "has locale" do
      assert_equal "en_US.UTF-8", @data["locale"]
    end

    it "has preferred language" do
      assert_equal "en", @data["preferred_language"]
    end

  end

  describe "bootserver fallback" do
    before(:each) do
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoDeviceImage = "organisationprefimage"
      test_organisation.save!
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )

      localboot_device = create_device(
        :puavoHostname => "localbootdevice",
        :macAddress => "00:60:2f:11:7A:7D",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )
      localboot_device.classes = ["top", "device", "puppetClient", "puavoLocalbootDevice"]
      localboot_device.save!

      @bootserver.puavoDeviceImage = "bootserverprefimage"
      @bootserver.save!

    end

    it "is used by thinclients " do
      get "/v3/devices/athin"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "bootserverprefimage", data["preferred_image"]
    end

    it "is not used by localboot devices" do
      get "/v3/devices/localbootdevice"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "organisationprefimage", data["preferred_image"]
    end

  end



  describe "device information with global default" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoAllowGuest = nil
      test_organisation.puavoPersonalDevice = nil
      test_organisation.save!
      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has allow guest" do
      assert_equal false, @data["allow_guest"]
    end

    it "has personal device" do
      assert_equal false, @data["personal_device"]
    end
  end

  describe "Device#preferred_boot_image" do
    it "is used for thinclients" do
      @thin = create_device(
        :puavoHostname => "athin",
        :puavoDeviceType =>  "thinclient",
        :macAddress => "00:60:2f:28:DC:51",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,

        :puavoDeviceBootImage => "bootimage",
        :puavoDeviceImage => "normalimage"
      )
      @thin.save!

      get "/v3/devices/athin"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "bootimage", data["preferred_boot_image"]
    end

    it "is preferred_image for fatclients" do
      @fat = create_device(
        :puavoHostname => "afat",
        :puavoDeviceType =>  "fatclient",
        :macAddress => "00:60:2f:E5:A1:37",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,

        :puavoDeviceBootImage => "bootimage",
        :puavoDeviceImage => "normalimage"
      )
      @fat.save!

      get "/v3/devices/afat"
      assert_200
      data = JSON.parse last_response.body
      assert_equal "normalimage", data["preferred_boot_image"]
    end

  end

  describe "error handling" do
    it "responds 404 for non existent device" do
      get "/v3/devices/notexists"
      assert_equal 404, last_response.status
      data = JSON.parse last_response.body
      assert_equal "NotFound", data["error"]["code"], data
    end

  end

  describe "device boot configuration" do
    before(:each) do
      @thinclient01 = create_device(
        :puavoHostname => "thinclient-01",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,
        :puavoDeviceBootImage => "deviceprefbootimage",
        :puavoDeviceImage => "deviceprefimage"
      )
      @thinclient02 = create_device(
        :puavoHostname => "thinclient-02",
        :macAddress => "bf:9a:8c:1b:e0:6b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,
        :puavoDeviceImage => "deviceprefimage"
      )
      @thinclient03 = create_device(
        :puavoHostname => "thinclient-03",
        :macAddress => "bf:9a:8c:1b:e0:6b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
      @thinclient04 = create_device(
        :puavoHostname => "thinclient-04",
        :macAddress => "bf:9a:8c:1b:e0:6b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school_without_fallback_value.dn
      )

      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoDeviceImage = "organisationprefimage"
      test_organisation.save!

      LdapModel.setup(
        :organisation =>
          PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
                      :credentials => { :dn => PUAVO_ETC.ldap_dn, :password => PUAVO_ETC.ldap_password }
      )
      @rest_thinclient01 = PuavoRest::Device.by_dn(@thinclient01.dn.to_s)
      @rest_thinclient02 = PuavoRest::Device.by_dn(@thinclient02.dn.to_s)
      @rest_thinclient03 = PuavoRest::Device.by_dn(@thinclient03.dn.to_s)
      @rest_thinclient04 = PuavoRest::Device.by_dn(@thinclient04.dn.to_s)
    end

    it "has preferred boot image by device" do
      assert_equal @rest_thinclient01.preferred_boot_image, "deviceprefbootimage"
    end

    it "has preferred boot image by device preferred image" do
      assert_equal @rest_thinclient02.preferred_boot_image, "deviceprefimage"
    end

    it "has preferred boot image by school preferred image" do
      assert_equal @rest_thinclient03.preferred_boot_image, "schoolprefimage"
    end
    it "has preferred boot image by organisation preferred image" do
      assert_equal @rest_thinclient04.preferred_boot_image, "organisationprefimage"
    end
    it "has not preferred boot image" do

    end
  end

  describe "wireless printer queues by device with school fallback" do

    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
    end

    it "has printer" do
      get "/v3/devices/athin/wireless_printer_queues", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal 1, data.count
      printer = data.first
      assert_equal "server1.example.opinsys.net", printer["server_fqdn"]
      assert_equal "printer1", printer["name"]
      assert_equal "printer1", printer["description"]
      assert_equal "ipp://server1.example.opinsys.net/printers/printer1", printer["remote_uri"]
    end

    it "can handle multiple printers" do

      printer2 = Printer.create(
        :printerDescription => "printer2",
        :printerLocation => "school2",
        :printerMakeAndModel => "foo",
        :printerType => "1234",
        :printerURI => "socket://baz",
        :puavoServer => @bootserver.dn
      )
      printer2.save!
      @school.add_wireless_printer(printer2)

      get "/v3/devices/athin/wireless_printer_queues", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body

      assert_equal 2, data.count
      assert(
        data.select do |p|
          p["name"] == "printer2"
        end.first,
        "must have the second printer"
      )
    end
  end

  describe "feed" do

    before(:each) do
      create_device(
        :puavoHostname => "feedthin",
        :macAddress => "00:60:2f:9B:93:FF",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
    end

    it "is empty without sources" do
      get "/v3/devices/feedthin/feed", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      data = JSON.parse last_response.body
      assert_equal [], data
    end

    it "can have data" do
      # TODO: add feed to redis, timetravel etc...
    end

  end

  describe "GET /v3/devices/_search" do
    before(:each) do
      create_device(
        :puavoHostname => "afat",
        :puavoDeviceType =>  "fatclient",
        :macAddress => "00:60:2f:E5:A1:37",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,

        :puavoDeviceBootImage => "bootimage",
        :puavoDeviceImage => "normalimage"
      ).save!

      create_device(
        :puavoHostname => "anotherdevive",
        :puavoDeviceType =>  "fatclient",
        :macAddress => "00:60:2f:7F:1F:FE",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,

        :puavoDeviceBootImage => "bootimage",
        :puavoDeviceImage => "normalimage"
      ).save!

    end

    it "can find device by hostname" do
      basic_authorize CONFIG["server"][:dn], CONFIG["server"][:password]
      get "/v3/devices/_search?q=afat"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal 1, data.size, data
      assert_equal "afat", data[0]["hostname"]
    end

    it "can find device by mac" do
      basic_authorize "uid=admin,o=puavo", "password"
      get "/v3/devices/_search?q=00:60:2f:7F:1F:FE"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal 1, data.size, data
      assert_equal "anotherdevive", data[0]["hostname"]
    end

  end

  describe "device information with invalid data" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn,
        :primary_user_uid => 'bob'
      )

      # device puavoDevicePrimaryUser is invalid when user 'bob' is removed
      @user.destroy

      get "/v3/devices/athin"
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has empty primary user" do
      assert_equal "", @data["primary_user"]
    end

  end

  describe "list of devices" do
    before(:each) do
      create_device(
        :puavoHostname => "athin",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
      create_device(
        :puavoHostname => "athin-02",
        :macAddress => "bf:9a:8c:1b:e0:7b",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
      get "/v3/devices", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has list of devices" do
      assert_equal Array, @data.class
    end

    it "has devices information on the list" do
      assert_equal "bf:9a:8c:1b:e0:6a", @data[0]["mac_address"]
      assert_equal "bf:9a:8c:1b:e0:7b", @data[1]["mac_address"]
    end

  end

  describe "device certificate" do
    before(:each) do
      @key = OpenSSL::PKey::RSA.new(2048)
      @csr = OpenSSL::X509::Request.new
      @csr.version = 0
      @csr.public_key = @key.public_key

      @csr.sign(@key, OpenSSL::Digest::SHA256.new)

      @device = create_device(
        :puavoHostname => "laptop-01",
        :puavoDeviceType => "laptop",
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoPreferredServer => @server1.dn,
        :puavoSchool => @school.dn
      )
    end

    it "sign new certificate" do
      basic_authorize @device.dn.to_s, @device.ldap_password

      post( "/v3/hosts/certs/sign",
            { "hostname" => "laptop-01",
              "certificate_request" => @csr.to_pem } )
      assert_200
      @data = JSON.parse last_response.body

      certificate = OpenSSL::X509::Certificate.new @data["certificate"]
      assert_equal "/CN=ca.example.opinsys.net", certificate.issuer.to_s
    end
  end
end
