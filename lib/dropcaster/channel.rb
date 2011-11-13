module Dropcaster
  #
  # Represents a podcast feed in the RSS 2.0 format
  #
  class Channel < DelegateClass(Hash)
    include ERB::Util # for h() in the ERB template
    include HashKeys

    MAX_KEYWORD_COUNT = 12

    # Instantiate a new Channel object. +sources+ must be present and can be a String or Array
    # of Strings, pointing to a one or more directories or MP3 files.
    #
    # +attributes+ is a hash with all attributes for the channel. The following attributes are
    # mandatory when a new channel is created:
    #
    # * <tt>:title</tt> - Title (name) of the podcast
    # * <tt>:url</tt> - URL to the podcast
    # * <tt>:description</tt> - Short description of the podcast (a few words)
    #
    def initialize(sources, attributes)
      super(Hash.new)

      # Assert mandatory attributes
      [:title, :url, :description].each{|attr|
        raise MissingAttributeError.new(attr) if attributes[attr].blank?
      }

      self.merge!(attributes)
      self.explicit = yes_no_or_input(attributes[:explicit])
      @source_files = Array.new

      if (sources.respond_to?(:each)) # array
        sources.each{|src|
          add_files(src)
        }
      else
        # single file or directory
        add_files(src)
      end

      # If not absolute, prepend the image URL with the channel's base to make an absolute URL
      unless self.image_url.blank? || self.image_url =~ /^https?:/
        Dropcaster.logger.info("Channel image URL '#{self.image_url}' is relative, so we prepend it with the channel URL '#{self.url}'")
        self.image_url = (URI.parse(self.url) + self.image_url).to_s
      end

      # If enclosures_url is not given, take the channel URL as a base.
      if self.enclosures_url.blank?
        Dropcaster.logger.info("No enclosure URL given, using the channel's enclosure URL")
        self.enclosures_url = self.url
      end

      # Warn if keyword count is larger than recommended
      assert_keyword_count(self.keywords)

      @channel_erb_template = Dropcaster.build_template(self.channel_template, 'channel.rss.erb')
    end

    #
    # Returns this channel as an RSS representation. The actual rendering is done with the help
    # of an ERB template. By default, it is expected as ../../templates/channel.rss.erb (relative to channel.rb).
    #
    def to_rss
      @channel_erb_template.result(binding)
    end

    #
    # Channel has_many items
    #
    # Returns all items (episodes) of this channel, ordered by newest-first.
    #
    def items
      all_items = Array.new
      @source_files.each{|src|
        item = Item.new(self, src, {:episode_template => self.episode_template})

        Dropcaster.logger.debug("Adding new item from file #{src}")

        # set author and image_url from channel if empty
        if item.artist.blank?
          Dropcaster.logger.info("#{src} has no artist, using the channel's author")
          item.tag.artist = self.author
        end

        if item.image_url.blank?
          Dropcaster.logger.info("#{src} has no image URL set, using the channel's image URL")
          item.image_url = self.image_url
        end

        # construct absolute URL, based on the channel's enclosures_url attribute
        item.url = (URI.parse(enclosures_url) + URI.encode(item.file_name))

        # Warn if keyword count is larger than recommended
        assert_keyword_count(item.keywords)

        all_items << item
      }

      # Print a warning if no episodes were found
      if 0 == all_items.size
        Dropcaster.logger.warn("No episodes found.")
      end

      # Sort result by newest first
      all_items.sort{|x, y| y.pub_date <=> x.pub_date}
    end

  private
    def add_files(src)
      if File.directory?(src)
        @source_files.concat(Dir.glob(File.join(src, '*.mp3')))
      else
        @source_files << src
      end
    end

    #
    # Deal with Ruby's autoboxing of Yes, No, true, etc values in YAML
    #
    def yes_no_or_input(flag)
      case flag
        when nil   : nil
        when true  : 'Yes'
        when false : 'No'
      else
        flag
      end
    end

    #
    # http://snippets.dzone.com/posts/show/4578
    #
    def truncate(string, count = 30)
      if string.length >= count
    		shortened = string[0, count]
    		splitted = shortened.split(/\s/)
    		words = splitted.length
    		splitted[0, words - 1].join(' ') + '…'
    	else
    		string
    	end
    end

    def assert_keyword_count(keywords)
      if keywords && MAX_KEYWORD_COUNT < keywords.size
        Dropcaster.logger.info("The list of keywords has #{keywords.size} entries, which exceeds the recommended maximum of #{MAX_KEYWORD_COUNT}.")
      end
    end
  end
end
