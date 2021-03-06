require_relative "./helper"

describe PuavoRest::Users do

  IMG_FIXTURE = File.join(File.dirname(__FILE__), "fixtures", "profile.jpg")

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoSchoolHomePageURL => "schoolhomepage.example"
    )

    @group = Group.new
    @group.cn = "group1"
    @group.displayName = "Group 1"
    @group.puavoSchool = @school.dn
    @group.puavoEduGroupType = "teaching group"
    @group.save!

    @role = Role.new
    @role.displayName = "Some role"
    @role.puavoSchool = @school.dn
    @role.groups << @group
    @role.save!

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :puavoLocale => "en_US.UTF-8",
      :mail => ["bob@example.com", "bob@foobar.com", "bob@helloworld.com"],
      :role_ids => [@role.puavoId],
      :puavoSshPublicKey => "asdfsdfdfsdfwersSSH_PUBLIC_KEYfdsasdfasdfadf"
    )

    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [
      Role.find(:first, {
        :attribute => "displayName",
        :value => "Maintenance"
      }).puavoId,
      @role.puavoId
    ]
    @user.save!

    @user2 = User.new(
      :givenName => "Alice",
      :sn  => "Wonder",
      :uid => "alice",
      :puavoEduPersonAffiliation => "student",
      :puavoLocale => "en_US.UTF-8",
      :mail => "alice@example.com",
      :role_ids => [@role.puavoId]
    )
    @user2.set_password "secret"
    @user2.puavoSchool = @school.dn
    @user2.role_ids = [
      Role.find(:first, {
        :attribute => "displayName",
        :value => "Maintenance"
      }).puavoId,
      @role.puavoId
    ]
    @user2.save!

    @user4 = User.new(
      :givenName => "Joe",
      :sn  => "Bloggs",
      :uid => "joe.bloggs",
      :puavoEduPersonAffiliation => "admin",
      :role_ids => [@role.puavoId]
    )

    @user4.set_password "secret"
    @user4.puavoSchool = @school.dn
    @user4.save!
    @school.add_admin(@user4)

  end

  describe "GET /v3/whoami" do
    it "returns information about authenticated user" do
      basic_authorize "bob", "secret"
      get "/v3/whoami"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
      assert_equal "bob@example.com", data["email"]
      assert_equal "student", data["user_type"]
      assert_equal "en", data["preferred_language"]
      assert data["uid_number"], "has uid number"
      assert data["gid_number"], "has gid number"
      assert_equal Fixnum, data["uid_number"].class, "uid number must be a Fixnum"

      assert data["organisation"], "has organisation data added"

      assert_equal "Example Organisation", data["organisation"]["name"]
      assert_equal "example.opinsys.net", data["organisation"]["domain"]
      assert_equal "dc=edu,dc=example,dc=fi", data["organisation"]["base"]
      assert_equal "bob@example.opinsys.net", data["domain_username"]
      assert_equal "schoolhomepage.example", data["homepage"]

      assert data["schools"], "has schools data added"
      assert_equal(1, data["schools"].size)
      assert(data["schools"].first["id"], "school data has id")
      assert_equal("Gryffindor", data["schools"].first["name"])

      group = data["schools"].first["groups"].first
      assert_equal "Group 1", group["name"]
      assert_equal "teaching group", group["type"]

      assert_equal "http://example.opinsys.net/v3/users/bob/profile.jpg", data["profile_image_link"]

      assert_equal "Europe/Helsinki", data["timezone"]

    end
  end

  describe "GET /v3/users" do
    it "lists all users" do
      basic_authorize "bob", "secret"
      get "/v3/users"
      assert_200
      data = JSON.parse(last_response.body)

      alice = data.select do |u|
        u["username"] == "alice"
      end.first

      assert(alice)
      assert_equal("Alice", alice["first_name"])
      assert_equal("Wonder", alice["last_name"])

      assert(data.select do |u|
        u["username"] == "bob"
      end.first)
    end

    it "lists all users with attribute limit" do
      basic_authorize "bob", "secret"
      get "/v3/users?attributes=username,first_name"
      assert_200
      data = JSON.parse(last_response.body)

      alice = data.select do |u|
        u["username"] == "alice"
      end.first

      assert(alice)
      assert_equal("Alice", alice["first_name"])
      assert_equal(nil, alice["last_name"])

      assert(data.select do |u|
        u["username"] == "bob"
      end.first)
    end


  end

  describe "GET /v3/users/_by_id/" do
    it "returns user data" do
      basic_authorize "bob", "secret"
      get "/v3/users/_by_id/#{ @user.puavoId }"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
    end
  end

  describe "GET /v3/users/bob" do

    it "organisation owner can see ssh_public_key of bob" do
      basic_authorize "cucumber", "cucumber"
      get "/v3/users/bob"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "asdfsdfdfsdfwersSSH_PUBLIC_KEYfdsasdfasdfadf", data["ssh_public_key"]
    end

    it "returns user data" do
      basic_authorize "bob", "secret"
      get "/v3/users/bob"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "bob", data["username"]
      assert_equal "Bob", data["first_name"]
      assert_equal "Brown", data["last_name"]
      assert_equal "bob@example.com", data["email"]
      assert_equal ["bob@foobar.com", "bob@helloworld.com"], data["secondary_emails"]
      assert_equal "student", data["user_type"]
      assert_equal "http://example.opinsys.net/v3/users/bob/profile.jpg", data["profile_image_link"]

      assert data["schools"], "has schools data added"
      assert_equal(1, data["schools"].size)
    end

    describe "with language fallbacks" do
      [
        {
          :name   => "user lang is the most preferred",
          :org    => "en_US.UTF-8",
          :school => "fi_FI.UTF-8",
          :user   => "sv_FI.UTF-8",
          :expect_language => "sv",
          :expect_locale => "sv_FI.UTF-8"
        },
        {
          :name   => "first fallback is school",
          :org    => "en_US.UTF-8",
          :school => "fi_FI.UTF-8",
          :user   => nil,
          :expect_language => "fi",
          :expect_locale => "fi_FI.UTF-8"
        },
        {
          :name   => "organisation is the least preferred",
          :org    => "en_US.UTF-8",
          :school => nil,
          :user   => nil,
          :expect_language => "en",
          :expect_locale => "en_US.UTF-8"
        },
      ].each do |opts|
        it opts[:name] do
          @user.puavoLocale = opts[:user]
          @user.save!
          @school.puavoLocale = opts[:school]
          @school.save!

          test_organisation = LdapOrganisation.first # TODO: fetch by name
          test_organisation.puavoLocale = opts[:org]
          test_organisation.save!

          basic_authorize "bob", "secret"
          get "/v3/users/bob"
          assert_200
          data = JSON.parse(last_response.body)
          assert_equal opts[:expect_language], data["preferred_language"]
          assert_equal opts[:expect_locale], data["locale"]
        end
      end
    end

    describe "with image" do
      before(:each) do
        @user.image = Rack::Test::UploadedFile.new(IMG_FIXTURE, "image/jpeg")
        @user.save!
      end

      it "returns user data with image link" do
        basic_authorize "bob", "secret"
        get "/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "http://example.opinsys.net/v3/users/bob/profile.jpg", data["profile_image_link"]
      end

      it "can be faked with VirtualHostBase" do
        basic_authorize "bob", "secret"
        get "/VirtualHostBase/http/fakedomain:1234/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "http://fakedomain:1234/v3/users/bob/profile.jpg", data["profile_image_link"]
      end

      it "does not have 443 in uri if https" do
        basic_authorize "bob", "secret"
        get "/VirtualHostBase/https/fakedomain:443/v3/users/bob"
        assert_200
        data = JSON.parse(last_response.body)

        assert_equal "https://fakedomain/v3/users/bob/profile.jpg", data["profile_image_link"]
      end

    end

    it "returns 401 without auth" do
      get "/v3/users/bob"
      assert_equal 401, last_response.status, last_response.body
      assert_equal "Negotiate", last_response.headers["WWW-Authenticate"], "WWW-Authenticate must be Negotiate for kerberos to work"
    end

    it "returns 401 with bad auth" do
      basic_authorize "bob", "bad"
      get "/v3/users/bob"
      assert_equal 401, last_response.status, last_response.body
    end
  end

  describe "GET /v3/users/bob/profile.jpg" do

    it "returns 200 if bob hash image" do
      @user.image = Rack::Test::UploadedFile.new(IMG_FIXTURE, "image/jpeg")
      @user.save!

      basic_authorize "bob", "secret"
      get "/v3/users/bob/profile.jpg"
      assert_200
      assert last_response.body.size > 10
    end

    it "returns the default anonymous image if bob has no image" do
      basic_authorize "bob", "secret"
      get "/v3/users/bob/profile.jpg"
      assert_200

      img_data = File.read(PuavoRest::Users::ANONYMOUS_IMAGE_PATH)
      hash = Digest::MD5.hexdigest(img_data)

      assert_equal(hash, Digest::MD5.hexdigest(last_response.body))
    end

    it "returns 401 without auth" do
      get "/v3/users/bob/profile.jpg"
      assert_equal 401, last_response.status, last_response.body
    end

  end

  describe "groups" do
    before(:each) do
      LdapModel.setup(
        :organisation => PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
        :credentials => {
          :dn => PUAVO_ETC.ldap_dn,
          :password => PUAVO_ETC.ldap_password }
      )
    end
    it "can be listed" do
      user = PuavoRest::User.by_username(@user.uid)
      group_names = Set.new(user.groups.map{ |g| g.name })
      assert !group_names.include?("Gryffindor"), "Group list must not include schools"

      assert_equal(
        Set.new(["Maintenance", "Group 1"]),
        group_names
      )
    end
  end

  describe "GET /v3/users/_search" do

    before(:each) do
      @user3 = User.new(
        :givenName => "Alice",
        :sn  => "Another",
        :uid => "another",
        :puavoEduPersonAffiliation => "student",
        :puavoLocale => "en_US.UTF-8",
        :mail => "alice.another@example.com",
        :role_ids => [@role.puavoId]
      )
      @user3.set_password "secret"
      @user3.puavoSchool = @school.dn
      @user3.role_ids = [
        Role.find(:first, {
          :attribute => "displayName",
          :value => "Maintenance"
        }).puavoId,
        @role.puavoId
      ]
      @user3.save!
    end

    it "can list bob" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=bob"
      assert_200
      data = JSON.parse(last_response.body)

      bob = data.select do |u|
        u["username"] == "bob"
      end.first

      assert bob

      assert bob["schools"], "has schools data added"
      assert_equal(1, bob["schools"].size)
    end

    it "can find bob with a partial match" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=bro"
      assert_200
      data = JSON.parse(last_response.body)

      bob = data.select do |u|
        u["username"] == "bob"
      end

      assert_equal 1, bob.size
    end

    it "can all alices" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=alice"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 2, data.size, data
    end

    it "can limit search with multiple keywords" do
      basic_authorize "bob", "secret"
      get "/v3/users/_search?q=alice+Wonder"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 1, data.size, data
      assert_equal "alice", data[0]["username"]
    end

    it "can find alice by email" do
      basic_authorize "cucumber", "cucumber"
      get "/v3/users/_search?q=alice@example.com"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 1, data.size, data
      assert_equal "alice", data[0]["username"]
    end

  end


  describe "PUT /v3/users/:username/administrative_groups" do

    before(:each) do

      LdapModel.setup(
        :organisation => PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
        :credentials => {
          :dn => PUAVO_ETC.ldap_dn,
          :password => PUAVO_ETC.ldap_password }
      )

      @user3 = PuavoRest::User.new(
        :first_name => "Jane",
        :last_name => "Doe",
        :username => "jane.doe",
        :roles => ["student"],
        :school_dns => [@school.dn.to_s]
      )
      @user3.save!

      @group2 = PuavoRest::Group.new(
        :name => "Test group 2",
        :abbreviation => "testgroup2",
        :type => "administrative group",
        :school_dn => @school.dn.to_s
      )
      @group2.save!


    end

    it "update administrative groups for user" do

      basic_authorize "joe.bloggs", "secret"

      put "/v3/users/#{ @user3.username }/administrative_groups",
        "ids" => [ @group2.id ]
      assert_200

      get "/v3/users/#{ @user3.username }/administrative_groups"
      assert_200
      data = JSON.parse(last_response.body)

      assert data[0]["member_usernames"].include?(@user3.username), "#{ @user3.username } is not member of group"
    end
  end

end
