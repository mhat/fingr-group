Camping.goes :Fingr

require 'xmpp4r-simple'
require 'rss/maker'
require 'date'
require 'yaml'

module Fingr::Models
  class Msg < Base
    has_many :taggings, :dependent => :destroy, :class_name => "Fingr::Models::Taggings"
    has_many :tags, :through => :taggings
    belongs_to :sender
    
    def sender_name
      sender ? sender.to_s : 'anonymous'
    end
  end

  class Tag < Base
    has_many :taggings, :dependent => :destroy, :class_name => "Fingr::Models::Taggings"
    has_many :msgs, :through => :taggings 

    def popularity
      case taggings.count
        when 0..2
          "not_popular"
        when 3..10
          "popular"
        else 
          "hella_popular"
      end
    end
  
  end
  
  class Taggings < Base
    belongs_to :msg
    belongs_to :tag
  end
  
  class Sender < Base
    has_many :msgs
    
    def to_s
      name || email
    end
  end

  class CreateDB < V 1.0
    def self.up
      create_table :fingr_msgs, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :body,       :string
        t.column :created_at, :datetime
      end
      Msg.create :body => "What's up, bitches?"
    end
    def self.down
      drop_table :msgs
    end
  end

  class AddTagSupport < V 1.1
    def self.up
      create_table :fingr_tags, :force => true do |t|
        t.column :name, :string, :null => false
      end
      add_index :fingr_tags, :name, :unique => true
      create_table :fingr_taggings do |t|
        t.column :tag_id,         :integer, :null => false
        t.column :msg_id,    :integer, :null => false
      end
      add_index :fingr_taggings, [:tag_id, :msg_id ], :unique => true
    end
    def self.down
      drop_table :fingr_tags
      drop_table :fingr_taggings
    end
  end

  class StripTags < V 1.2
    def self.up
      msgs = Msg.find(:all)
      msgs.each do |m|
        if (m.body.match(/^(\w+):\s+(.*)$/))
          m.body = $2
          m.save!
          t = Fingr::Models::Tag.find_or_create_by_name($1)
          Fingr::Models::Taggings.create :msg => m, :tag => t if t
        end
      end
    end
    
    def self.down
        # NO NEED TO GO BACKWARDS
    end
  end
  
  class AddSenders < V 1.3
    def self.up
      create_table :fingr_senders, :force => true do |t|
        t.column :name,       :string
        t.column :email,      :string
        t.column :created_at, :datetime
      end
      
      add_column :fingr_msgs, :sender_id, :integer
    end
  end
end


module Fingr::Controllers
  class Style < R '/styles.css'
    def get
      @headers["Content-Type"] = "text/css; charset=utf-8"
      @body = %{
        body {
	        font-family: Verdana, Arial, Helvetica, sans-serif;
	        font-size: 11px;
	        background-color: #FFFFFF;
	        color: #666;
        }
        a:link, a:visited, a:active {
	        color: #999;
	        text-decoration: none;
        }
        a:hover {
	        text-decoration: underline;
	        color: #FF9900;
        }
        #container {
          width: 600px;
          margin: 50px auto 0px auto;
        }
        #thebox {
	        width: 450px;
	        background-color: white;
	        color: #666;
            margin-right: 150px;
        }
        #tagbox {
          float: right;
          width: 100px;
        }
        a.not_popular { font-size: 1em }
        a.popular { font-size: 1.9em }
        a.hella_popular { font-size: 2.6em }
        .datebox {
            border: 1px #cccccc solid;
            width: 450px;
	        padding: 0px 20px 20px 20px;
            margin-bottom: 20px;
        } 
        #pimpbox {
            width: 450px;
            text-align: right; 
        }
        h1 {
            font-size: 12px;
        }
        p { 
            margin-left: 10px;
            color: red;
            border-bottom: 1px dotted #cccccc
        }
        p span.body {
        }
        p span.sender {
            float: right;
            margin-left: 10px;
            color: #ccc;
        }
      }
    end
  end

  class Index < R '/'
    def get
      @msg_list = Hash.new
      @msgs = Msg.find(:all, :order => "id DESC", :limit => 30)
      
      @msgs.each do |m|
        if (!@msg_list.has_key?(m.sender_name))
          @msg_list[m.sender_name] = Array.new
        end
        @msg_list[m.sender_name].push(m) 
      end
      render :index
    end
  end
  
  class Message < R '/msg/(\d+)'
    def get msg_id
      begin
        @m = Msg.find(msg_id)
        render :message 
      rescue ActiveRecord::RecordNotFound
        redirect Index
      end
    end
  end

  class Day < R '/date/(\d{4}-\d{2}-\d{2})'
    def get date
      @msg_list = Msg.find(:all, :order => "created_at DESC", :conditions => "created_at like '#{date}%'")
      render :list
    end
  end
 
  class Tags < R '/tags/(\w+)'
    def get tag
      begin
        tag = Tag.find_by_name(tag)
        @msg_list = tag.taggings.collect { | t | t.msg }
        render :list
      rescue ActiveRecord::RecordNotFound
        redirect Index
      end
    end 
  end 

  class Feed < R '/feed.xml'
    def get
      version = "1.0"
      feed = RSS::Maker.make(version) do |f|
        f.channel.title = "Fingr feed"
        f.channel.link  = R(Index)
        f.channel.description = "Feed Description"
        f.channel.about = "ABOUT?"
        f.items.do_sort = true

        @msgs = Msg.find(:all, :order => "created_at DESC", :limit => 30)
        for m in @msgs do
          i = f.items.new_item
          i.link = R(Message, m.id)
          i.date = m.created_at
          i.title = m.body
        end
      end
    end
  end
end

module Fingr::Views
  def layout
    html do
      head do
        title "Fingr?"
        link :rel   => 'stylesheet',
             :type  => 'text/css',
             :href  => '/styles.css',
             :media => 'screen'
      end
      body do
        div.container! do
          div.tagbox! do
              Fingr::Models::Tag.find(:all).each do |tag| 
                a tag.name, :href => R(Tags, tag.name), :class => tag.popularity
                text "<br />" 
            end
          end
          div.thebox do
            self << yield 
          end
          div.pimpbox! do
            p { "Powered By <a href='http://github.com/mhat/fingr-group'>Fingr-Group</a>" }
          end
        end
      end
    end
  end

  def index
    @msg_list.sort.each do |sender_name, msg_array|
      
      msg_array = msg_array[0..9] if msg_array.size > 10
      
      div.datebox do
        h1 { a sender_name }
        msg_array.sort{|a,b| b.created_at <=> a.created_at }.each do |msg|
          p do
            span.body { msg.body }
            span.sender { msg.created_at.strftime("%a %d %H:%m") }
          end
        end
      end
    end
  end

  def message
    div.datebox do
      h1 Date.parse(@m.created_at.to_s).to_s
    end
  end
  
  def list
    div.datebox do
      h1 {Date.parse(@msg_list[0].created_at.to_s).to_s}
      @msg_list.each do |m|
        p m.body
      end
    end
  end
end

module Fingr 
  @conf  = YAML.load_file('config.yml') #TODO: do something with Errno::ENOENT
  @J = Jabber::Simple.new(@conf["username"], @conf["password"])
  def self.grab_messages
    @J.received_messages do |msg|
      catch :done do
        msg_sender = msg.from.node + "@" + msg.from.domain
        unless @conf["listen_to"].any?{|u| u if Regexp.new(u, 'i') =~ msg_sender}
          @J.deliver(msg.from, "LEAVE ME ALONE!  YOU DON'T KNOW ME!")
        else 
          sender = Fingr::Models::Sender.find_or_create_by_email(msg_sender)
          
          case msg.body
          when /^call me (.+)$/
            sender.update_attribute :name, $1.strip
            @J.deliver(msg.from, "okay, I'll call you #{sender.name} from now on")
            throw :done
          when /^(\w+):\s+(.*)$/
            msg.body = $2
            t = Fingr::Models::Tag.find_or_create_by_name($1)
          end
          
          if msg.type == :chat
            m = Fingr::Models::Msg.create :body => msg.body, :sender => sender
            Fingr::Models::Taggings.create :msg => m, :tag => t if t
          end
        end
      end
    end
  end
  def self.create
    Fingr::Models.create_schema :assume => ( Fingr::Models::Msg.table_exists? ? 1.0 : 0.0 )
    Thread.new { loop { Fingr::grab_messages; sleep 10 } }
  end
end
