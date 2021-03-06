require 'rails_helper'

RSpec.describe "TopLevel", type: :request do
  describe "GET /" do
    it "serves index page" do
      get root_path
      expect(response).to be_successful
    end

    # TODO
    # it "serves ride zone ride request page" do
    #   ride_zone = create(:ride_zone)
    #   get "/ride/#{ride_zone.id}"
    #   expect(response).to be_successful
    # end

    it "redirects old ride zone ride request page" do
      ride_zone = create(:ride_zone)
      get "/get_a_ride/#{ride_zone.id}"
      expect(response).to have_http_status(301)
    end


    # TODO
    # it "serves the generic volunteer page" do
    #   get "/volunteer_to_drive"
    #   expect(response).to be_successful
    # end

    # TODO
    # it "serves ride zone volunteer page" do
    #   ride_zone = create(:ride_zone)
    #
    #   get "/volunteer/#{ride_zone.slug}"
    #   expect(response).to be_successful
    # end

    # TODO
    # it "404s a bad volunteer page" do
    #   get "/volunteer/blarg"
    #   expect(response).to have_http_status(404)
    # end



    it "redirects the old ride zone volunteer page" do
      ride_zone = create(:ride_zone)

      get "/volunteer_to_drive/#{ride_zone.id}"
      expect(response).to have_http_status(301)
    end

    it "serves confirm page" do
      get confirm_path
      expect(response).to be_successful
    end

    it "serves about page" do
      get about_path
      expect(response).to be_successful
    end

    it "serves code_of_conduct page" do
      get code_of_conduct_path
      expect(response).to be_successful
    end

    it "serves terms_of_service page" do
      get terms_of_service_path
      expect(response).to be_successful
    end

    it "serves privacy page" do
      get privacy_path
      expect(response).to be_successful
    end

    describe "lower-environment warning banner" do 
      it "should show a warning banner when in staging (or other non-prod)" do 
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("staging"))
        get "/"
        expect(response.body).to include("You are viewing the")
        expect(response.body).to include("<strong>STAGING</strong>")
      end
  
      it "should NOT show a warning banner when in production" do 
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        get "/"
        expect(response.body).to_not include("You are viewing the")
        expect(response.body).to_not include("<strong>PRODUCTION</strong>")
      end  
    end

  end
end
