require 'rails_helper'

RSpec.describe Conversation, type: :model do
  #it_behaves_like 'to_from_addressable'

  let(:ride_address_attrs) {{from_address: '106 Dunbar Avenue', from_city: 'Carnegie',
                             from_latitude: 40.409, from_longitude: -80.090,
                             to_address: 'to', to_city: 'tcity', to_latitude: 3, to_longitude: 4}}
  let(:full_address_attrs) { {from_latitude: 40.4, from_longitude: -80.1, from_confirmed: true, to_latitude: 40.4, to_longitude: -80.1, to_confirmed: true} }

  describe 'creation' do
    context 'from ride' do
      let(:ride) { create :scheduled_ride }

      it "works" do
        ride.voter.phone_number_normalized = ''
        returned_conversation = Conversation.create_from_ride(ride, 'foo')
        expect(returned_conversation).to be_instance_of(Conversation)
      end
    end
  end

  describe 'has_fields_for_ride?' do
    context 'has what it needs to create a ride' do
      let(:convo) { create :complete_conversation }
      it 'return true' do
        expect(convo.has_fields_for_ride?).to eq(true)
      end
    end

    context 'is missing from_address' do
      let(:convo) { create :complete_conversation, from_address: nil }
      it 'return false' do
        expect(convo.has_fields_for_ride?).to eq(false)
      end
    end

    context 'is missing from_city' do
      let(:convo) { create :complete_conversation, from_city: nil }
      it 'return false' do
        expect(convo.has_fields_for_ride?).to eq(false)
      end
    end

    context 'is missing from_latitude' do
      let(:convo) { create :complete_conversation, from_latitude: nil }
      it 'return false' do
        expect(convo.has_fields_for_ride?).to eq(false)
      end
    end

    context 'is missing from_longitude' do
      let(:convo) { create :complete_conversation, from_longitude: nil }
      it 'return false' do
        expect(convo.has_fields_for_ride?).to eq(false)
      end
    end

    context 'is missing pickup_at' do
      let(:convo) { create :complete_conversation, pickup_at: nil }
      it 'return false' do
        expect(convo.has_fields_for_ride?).to eq(false)
      end
    end
  end

  describe 'validations' do
    describe 'phone_numbers_match_first_message' do
      let(:convo) { create :conversation }

      context 'Conversation has no messages' do
        it 'should be valid' do
          expect(convo.messages.count).to eq(0)
          convo.to_phone = nil
          convo.from_phone = nil
          expect(convo).to be_valid
          end
      end

      context 'Conversation has messages' do
        context 'message to/from match' do
          it 'should be valid' do
            create :message, conversation: convo, to: convo.to_phone, from: convo.from_phone
            create :message, conversation: convo, to: convo.to_phone, from: convo.from_phone

            expect(convo).to be_valid
          end
        end
      end

      context 'message to/from do not match' do
        it 'should not be valid' do
          create :message, conversation: convo, to: convo.to_phone, from: convo.from_phone
          create :message, conversation: convo, to: convo.to_phone, from: convo.from_phone

          convo.to_phone = '111-111-1111'
          convo.from_phone ='222-222-2222'

          expect(convo).to_not be_valid
        end
      end
    end

    describe 'validate_voter_phone_not_blacklisted' do
      let(:convo) { create :conversation_with_messages}

      context 'voter phone is blacklisted' do
        it 'should not be valid' do
          convo.blacklist_voter_phone

          new_convo = build :conversation, from_phone: convo.from_phone

          expect(new_convo).to_not be_valid
        end
      end

      context 'voter phone is not blacklisted' do
        it 'should be valid' do
          convo.blacklist_voter_phone

          new_convo = build :conversation, from_phone: '111-111-1112'

          expect(new_convo).to be_valid
        end
      end
    end
  end

  describe 'readable strings' do
    it 'titleizes status' do
      expect(Conversation.new(status: 'ride_created').status_str).to eq('Ride Created')
    end

    it 'titleizes lifecycle' do
      expect(Conversation.new(lifecycle: 'info_complete').lifecycle_str).to eq('Info Complete')
    end
  end

  describe 'lifecycle hooks' do

    describe 'saving status' do
      let(:user) { create :user, language:1, name: 'foo' }

      it 'writes lifecycle to db' do
        c = create :conversation, user: user
        expect(c.reload.lifecycle).to eq('have_name')
      end

      it 'auto updates status' do
        c = create :conversation, user: user, status: :sms_created
        c.reload.update_attribute(:additional_passengers, 2)
        expect(c.reload.status).to eq('in_progress')
      end
    end
  end

  describe 'new conversation from staff' do
    let(:rz) { create :ride_zone }
    let(:user) { create :driver_user, rz: rz }
    let(:body) { 'can you go to south side?' }
    let(:twilio_msg) { OpenStruct.new(error_code: nil, status: 'delivered', body: body, sid: 'sid', from: rz.phone_number_normalized, to: user.phone_number_normalized) }

    before :each do
      allow(TwilioService).to receive(:send_message).and_return(twilio_msg)
    end

    it 'calls twilio service' do
      expect(TwilioService).to receive(:send_message).and_return(twilio_msg)
      Conversation.create_from_staff(rz, user, body, 5)
    end

    it 'handles twilio error and creates conversation' do
      expect(TwilioService).to receive(:send_message).and_return(OpenStruct.new(error_code: 123))
      expect(Conversation.create_from_staff(rz, user, body, 5).class).to eq(Conversation)
      msg = Conversation.last.messages.last
      expect(msg.sent_by).to eq('Staff')
      expect(msg.body =~ /#{body}/).to be_truthy
    end

    it 'creates a conversation and message' do
      Conversation.create_from_staff(rz, user, body, 5)
      expect(Conversation.count).to eq(1)
      expect(Conversation.last.staff_initiated?).to be_truthy
      msg = Conversation.last.messages.last
      expect(msg.sent_by).to eq('Staff')
      expect(msg.body).to eq(body)
    end
  end

  describe 'user language' do
    let(:rz) { create :ride_zone }
    let(:user) { create :user, language: :es }
    let(:convo) { create :complete_conversation, ride_zone: rz, user: user, pickup_at: 5.minutes.from_now }

    it 'reports user language' do
      expect(convo.user_language).to eq('es')
    end

    it 'reports language if unknown' do
      user.update_attribute(:language, :unknown)
      expect(convo.user_language).to eq('en')
    end
  end

  describe 'attempt confirmation' do
    let(:rz) { create :ride_zone }
    let(:user) { create :user, language: :en }
    let(:convo) { create :complete_conversation, ride_zone: rz, user: user, pickup_at: 5.minutes.from_now }
    let!(:ride) { Ride.create_from_conversation(convo) }
    let(:body) { 'confirm' }
    let(:twilio_msg) { OpenStruct.new(error_code: nil, status: 'delivered', body: body, sid: 'sid', from: convo.from_phone, to: convo.to_phone) }

    before :each do
      allow(TwilioService).to receive(:send_message).and_return(twilio_msg)
    end

    it 'calls twilio service' do
      expect(TwilioService).to receive(:send_message).and_return(twilio_msg)
      convo.attempt_confirmation
    end

    it 'updates ride confirmed to false' do
      convo.attempt_confirmation
      expect(convo.reload.ride_confirmed).to eq(false)
    end

    it 'creates a message from bot' do
      convo.attempt_confirmation
      expect(convo.reload.messages.last.sent_by).to eq('Bot')
    end

    it 'auto confirms ride if twilio error' do
      expect(Conversation).to receive(:send_staff_sms).and_return('Conversation error 30005')
      convo.attempt_confirmation
      expect(convo.reload.ride_confirmed).to be_truthy
      expect(ride.reload.status).to eq('waiting_assignment')
    end

    [false, true].each do |val|
      it "does not call twilio if ride confirmed is #{val}" do
        expect(TwilioService).to_not receive(:send_message)
        convo.update_attribute(:ride_confirmed, val)
        convo.attempt_confirmation
      end
    end

    it 'bumps to waiting_assignment when time goes by' do
      convo.attempt_confirmation
      ride.update_attribute(:pickup_at, 5.minutes.ago)
      convo.attempt_confirmation
      expect(convo.reload.status).to eq('ride_created')
      expect(convo.lifecycle).to eq('info_complete')
      expect(ride.reload.status).to eq('waiting_assignment')
    end

    it 'does not bump to waiting_assignment if driver assigned' do
      convo.attempt_confirmation
      ride.update_attributes(pickup_at: 5.minutes.ago, status: :driver_assigned)
      convo.attempt_confirmation
      expect(convo.reload.status).to eq('ride_created')
      expect(ride.reload.status).to eq('driver_assigned')
    end

    it 'handles twilio error' do
      expect(TwilioService).to receive(:send_message).and_return(OpenStruct.new(error_code: 123))
      convo.attempt_confirmation
      expect(convo.reload.ride_confirmed).to be_nil
    end
  end

  describe 'notification of driver assigned' do
    let(:rz) { create :ride_zone }
    let(:user) { create :user, language: :en }
    let(:driver) { create :driver_user, rz: rz, name: 'FOO', description: 'BAR', license_plate: 'LP' }
    let(:convo) { create :conversation_with_messages, ride_zone: rz, user: user, pickup_at: 5.minutes.from_now }
    let(:body) { 'FOO has been assigned - look for a BAR - LP'}
    let(:twilio_msg) { OpenStruct.new(error_code: nil, status: 'delivered', body: body, sid: 'sid', from: rz.phone_number_normalized, to: user.phone_number_normalized) }

    before :each do
      allow(TwilioService).to receive(:send_message) { |payload|
        expect(payload[:body] =~ /FOO.*BAR - LP/).to_not be_nil # as formatted by conversation
      }.and_return(twilio_msg)
    end

    it 'calls twilio service' do
      expect(TwilioService).to receive(:send_message).and_return(twilio_msg)
      convo.notify_voter_of_assignment(driver)
    end

    it 'creates a message from bot' do
      convo.notify_voter_of_assignment(driver)
      expect(convo.reload.messages.last.sent_by).to eq('Bot')
    end

    it 'formats message with driver name and vehicle info' do
      convo.notify_voter_of_assignment(driver)
      expect(convo.reload.messages.last.body =~ /FOO.*BAR - LP/).to_not be_nil
    end

    it 'uses cleared message with no driver' do
      expect(TwilioService).to receive(:send_message) {|args|
        expect(args[:body]).to eq(I18n.t(:driver_cleared, locale: :en))
      }.and_return(twilio_msg)
      convo.notify_voter_of_assignment(nil)
    end
  end

  describe 'event generation' do
    it 'sends new conversation event' do
      expect(RideZone).to receive(:event).with(anything, :new_conversation, anything)
      create :conversation
    end

    it 'sends conversation update event' do
      c = create :conversation
      expect(RideZone).to receive(:event).with(c.ride_zone_id, :conversation_changed, anything)
      c.update_attribute(:status, :closed)
    end
  end

  it 'updates status on ride assignment' do
    r = create :ride
    c = create :conversation
    r.conversation = c
    expect(c.reload.status).to eq('ride_created')
  end

  it 'inverts ride addresses' do
    r = create :ride, ride_address_attrs
    c = create :conversation
    c.invert_ride_addresses(r)
    c.reload
    expect(c.from_address).to eq('to')
    expect(c.from_city).to eq('tcity')
    expect(c.from_latitude).to eq(3)
    expect(c.from_longitude).to eq(4)
    expect(c.to_address).to eq('106 Dunbar Avenue')
    expect(c.to_city).to eq('Carnegie')
    expect(c.to_latitude.to_f).to eq(40.409)
    expect(c.to_longitude.to_f).to eq(-80.090)
  end

  it 'updates status timestamp on create' do
    c = create :conversation
    expect(c.reload.status_updated_at).to_not be_nil
  end

  it 'updates status timestamp on status change' do
    c = Timecop.travel(1.hour.ago) do
      create :conversation
    end
    c.update_attribute(:status, :closed)
    expect(Time.now - c.reload.status_updated_at).to be <(10)
  end

  describe 'lifecycle calculation' do
    it 'detects newly created' do
      c = create :conversation
      expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:created])
    end

    it 'detects language exists' do
      c = create :conversation
      c.user.update_attributes language: 1, name: ''
      expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_language])
    end

    it 'detects confirmation required' do
      c = create :conversation, status: :ride_created, ride_confirmed: false
      expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:requested_confirmation])
    end

    it 'detects confirmation received' do
      c = create :conversation, status: :ride_created, ride_confirmed: true
      expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:info_complete])
    end

    describe 'user attributes known' do
      let(:user) { create :user, language: 1, name: 'foo' }

      it 'detects language and name exist' do
        c = create :conversation, user: user
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_name])
      end

      it 'detects existing ride' do
        create :ride, {voter: user, status: :complete}.merge(ride_address_attrs)
        c = create :conversation, user: user
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_prior_ride])
      end

      it 'ignores existing ride to unknown destination' do
        create :ride, {voter: user, status: :complete}.merge(ride_address_attrs).merge(to_address: Ride::UNKNOWN_ADDRESS)
        c = create :conversation, user: user
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_name])
      end

      it 'detects existing ride has been copied' do
        r = create :ride, {voter: user, status: :complete}.merge(ride_address_attrs)
        c = create :conversation, user: user
        c.invert_ride_addresses(r)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_confirmed_destination])
      end

      it 'detects origin exists' do
        c = create :conversation, user: user, from_latitude: 34.5, from_longitude: -122.6
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_origin])
      end

      it 'detects confirmed origin' do
        c = create :conversation, user: user, from_latitude: 34.5, from_longitude: -122.6, from_confirmed: true
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_confirmed_origin])
      end

      it 'detects unknown destination' do
        c = create :conversation, user: user, from_latitude: 34.5, from_longitude: -122.6, from_confirmed: true
        c.set_unknown_destination
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_confirmed_destination])
      end

      it 'detects destination exists' do
        c = create :conversation, user: user, from_latitude: 34.5, from_longitude: -122.6, from_confirmed: true, to_latitude: 34.5, to_longitude: -122.6
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_destination])
      end

      it 'detects confirmed destination' do
        c = create :conversation, {user: user}.merge(full_address_attrs)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_confirmed_destination])
      end

      it 'detects time exists' do
        c = create :conversation, {user: user}.merge(full_address_attrs).merge(pickup_at: Time.now)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_time])
      end

      it 'detects time confirmed' do
        c = create :conversation, {user: user}.merge(full_address_attrs).merge(pickup_at: Time.now, time_confirmed: true)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_confirmed_time])
      end

      it 'detects passengers' do
        c = create :conversation, {user: user}.merge(full_address_attrs).merge(pickup_at: Time.now, time_confirmed: true, additional_passengers: 0)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_passengers])
      end

      it 'detects time exists unknown dest' do
        c = create :conversation, {user: user}.merge(full_address_attrs).merge(pickup_at: Time.now).merge(to_address: Conversation::UNKNOWN_ADDRESS)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_time])
      end

      it 'detects time confirmed unknown dest' do
        c = create :conversation, {user: user}.merge(full_address_attrs).merge(pickup_at: Time.now, time_confirmed: true).merge(to_address: Conversation::UNKNOWN_ADDRESS)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_confirmed_time])
      end

      it 'detects passengers unknown dest' do
        c = create :conversation, {user: user}.merge(full_address_attrs).merge(pickup_at: Time.now, time_confirmed: true, additional_passengers: 0).merge(to_address: Conversation::UNKNOWN_ADDRESS)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:have_passengers])
      end

      it 'detects complete' do
        c = create :complete_conversation, user: user
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:info_complete])
      end

      it 'detects complete unknown dest' do
        c = create :complete_conversation, user: user, to_address: Conversation::UNKNOWN_ADDRESS
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:info_complete])
      end

      it 'detects requested confirmation' do
        c = create :complete_conversation, user: user, ride_confirmed: false
        Ride.create_from_conversation(c)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:requested_confirmation])
      end

      it 'detects confirmation done' do
        c = create :complete_conversation, user: user, ride_confirmed: true
        Ride.create_from_conversation(c)
        expect(c.send(:calculated_lifecycle)).to eq(Conversation.lifecycles[:info_complete])
      end
    end
  end

  describe 'finds unreachable phone errors' do
    it 'matches error codes' do
      expect(Conversation.unreachable_phone_error('Conversation error 30003')).to be_truthy
      expect(Conversation.unreachable_phone_error('Conversation error 30005')).to be_truthy
      expect(Conversation.unreachable_phone_error('Conversation error 30006')).to be_truthy
    end

    it 'does not match other errors' do
      expect(Conversation.unreachable_phone_error('Twilio error invalid number')).to be_falsey
    end

    it 'ignores non-strings' do
      expect(Conversation.unreachable_phone_error(OpenStruct.new(sms_id: 'foo'))).to be_falsey
    end
  end

  describe 'closing' do
    let(:convo) { create :conversation_with_messages }
    let(:driver) { create :driver_user, rz: convo.ride_zone }
    let(:ride) { r = Ride.create_from_conversation(convo); r.assign_driver(driver); r }

    it 'closes the conversation' do
      convo.close('user')
      expect(convo.reload.status).to eq('closed')
    end

    it 'completes the ride' do
      ride
      convo.close('foobar')
      expect(convo.reload.status).to eq('closed')
      expect(ride.reload.status).to eq('canceled')
      expect(ride.description =~ /foobar/).to be_truthy
      expect(ride.driver).to be_nil
    end
  end

  it 'escapes api json' do
    str = 'So & and <img>'
    safe = CGI::escape_html(str)
    u = create :user, name: str
    c = create :conversation, user: u, from_address: str, from_city: str, to_address: str, to_city: str, special_requests: str
    m = create :message, conversation: c, body: str, from: c.from_phone, to: c.to_phone
    j = c.api_json
    %w(from_address from_city to_address to_city special_requests last_message_body name).each do |field|
      expect(j[field]).to eq(safe)
    end
  end

  describe 'Conversation' do
    let(:convo) { create :complete_conversation }
    let(:driver) { create :driver_user, rz: convo.ride_zone }
    let(:ride) { r = Ride.create_from_conversation(convo); r }

    # Conversation.update_ride_conversation_from_ride(@ride)
    it 'updates from_address of the ride conversation from the ride itself' do
      expect(ride.from_address).to eq(convo.from_address)
      ride.from_address = 'The Moon'
      Conversation.update_ride_conversation_from_ride(ride)
      expect(convo.reload.from_address).to eq('The Moon')
    end

    it 'updates from_phone of the ride conversation from the ride itself' do
      expect(ride.voter.phone_number).to eq(convo.user.phone_number)
      ride.voter.phone_number = '8675309'
      Conversation.update_ride_conversation_from_ride(ride)
      expect(convo.reload.from_phone).to eq('8675309')
    end
  end

end
