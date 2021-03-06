require 'rails_helper'

RSpec.describe Message, type: :model do

  it { should belong_to(:conversation) }
  it { should belong_to(:ride_zone) }

  describe 'validations' do

    it { should validate_presence_of :conversation }

    describe 'conversation_has_correct_phone_numbers' do
      let(:convo) { create :conversation}
      let(:convo_with_messages) { create :conversation_with_messages}
      let(:message) { build :message }

      context 'Message is first message' do
        context 'convo to/from match' do
          it 'should be valid' do
            convo = create :conversation, to_phone: message.to, from_phone: message.from
            message.conversation = convo

            expect(message).to be_valid
          end
        end
      end

      context 'convo to/from do not match' do
        it 'should not be valid' do
          message.conversation = convo

          expect(message).to_not be_valid
        end
      end

      context 'Message is no first message' do
        it 'should be valid' do
          message.conversation = convo_with_messages

          expect(message).to be_valid
        end
      end
    end
  end

  describe 'reply to conversation' do
    let(:twilio_msg) { OpenStruct.new(sid: 'sid', status: 'status', body: 'hello', from: 'from', to: 'to') }

    it 'should update the conversation' do
      c = create :conversation_with_messages, status: :in_progress
      Message.create_conversation_reply(c, twilio_msg)
      expect(c.reload.status).to eq('help_needed')
    end

    it 'should not update if ride created' do
      c = create :conversation_with_messages, status: :ride_created
      Message.create_conversation_reply(c, twilio_msg)
      expect(c.reload.status).to eq('ride_created')
    end
  end

  describe 'staff messages' do
    let(:ride_zone) { create :ride_zone }
    let(:user) { create :driver_user, rz: ride_zone }
    let(:convo) { create :conversation, user: user, ride_zone: ride_zone, from_phone: ride_zone.phone_number, to_phone: user.phone_number }
    let(:twilio_msg) { OpenStruct.new(sid: 'sid', status: 'status', body: 'hello', from: convo.from_phone, to: convo.to_phone) }

    it 'should create the message' do
      msg = Message.create_from_staff(convo, twilio_msg)
      expect(msg.body).to eq('hello')
      expect(msg.sent_by).to eq('Staff')
    end

    it 'should create bot message' do
      msg = Message.create_from_bot(convo, twilio_msg)
      expect(msg.body).to eq('hello')
      expect(msg.sent_by).to eq('Bot')
    end
  end

  describe 'user initiated conversation' do
    let(:ride_zone) { create :ride_zone }
    let(:user) { create :voter_user, rz: ride_zone }
    let(:convo) { create :conversation_with_messages, user: user, ride_zone: ride_zone, from_phone: user.phone_number, to_phone: ride_zone.phone_number }
    let(:twilio_msg) { OpenStruct.new(sid: 'sid', status: 'status', body: 'hello', from: convo.from_phone, to: convo.to_phone) }

    it 'should create the message' do
      msg = Message.create_from_staff(convo, twilio_msg)
      expect(msg.body).to eq('hello')
      expect(msg.sent_by).to eq('Voter')
    end
  end

  describe 'event generation' do
    let!(:convo) { create :conversation_with_messages }

    it 'sends new message event' do
      expect(RideZone).to receive(:event).with(anything, :new_message, anything)
      expect(RideZone).to receive(:event).with(anything, :conversation_changed, anything)
      create :message, conversation: convo
    end

    it 'sends message update event' do
      m = create :message, conversation: convo
      expect(RideZone).to receive(:event).with(anything, :message_changed, anything)
      m.update_attribute(:sms_status, 'rejected')
    end
  end

  it 'reports sent by voter' do
    convo = create :conversation_with_messages
    msg = create :message, conversation: convo, to: convo.to_phone, from: convo.from_phone
    expect(msg.sent_by).to eq('Voter')
  end

  it 'reports sent by driver' do
    convo = create :conversation_with_messages
    convo.user.add_role(:driver, convo.ride_zone)
    msg = create :message, conversation: convo, to: convo.to_phone, from: convo.from_phone
    expect(msg.sent_by).to eq('Driver')
  end

  it 'reports sent by staff' do
    convo = create :conversation_with_messages
    msg = create :message, conversation: convo, from: convo.to_phone, to: convo.from_phone, sms_status: 'queued'
    expect(msg.sent_by).to eq('Staff')
  end

  it 'reports sent by bot' do
    convo = create :conversation_with_messages
    msg = create :message, conversation: convo, from: convo.to_phone, to: convo.from_phone
    expect(msg.sent_by).to eq('Bot')
  end

  it 'escapes html in body' do
    convo = create :conversation_with_messages
    msg = create :message, conversation: convo, body: 'Test <img>'
    expect(msg.api_json['body']).to eq('Test &lt;img&gt;')
  end
end
