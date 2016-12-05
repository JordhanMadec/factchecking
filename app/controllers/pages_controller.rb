require 'twitter'

class PagesController < ApplicationController
  def init
    client = Twitter::REST::Client.new do |config|
      config.consumer_key = "xpg49pUpKolcCXWuQe2b0EqYx"
      config.consumer_secret = "aqMRdUn28HqZrD1IIeXK6Pk0SfliFQGDuplBkZnlVo4cMvyaHo"
      config.access_token = "720567318443634689-4K5Xns30llMvExfUZG1IaBFrIqUe32q"
      config.access_token_secret = "hp31Ax4ZzAjaMikgsOwjHidqVhxxeE3kGDnBS6QT2Vo2K"
    end
  end

  def home
    
  end

  def search_tweets
    client = init
    #@twittos = client.user(params[:keywords])
    #@tweet_list = client.user_timeline(params[:keywords],).take(100)
    @keywords = params[:keywords] ||= "test"
    @tweet_list = client.search(@keywords, lang: "fr")
    @nbTweets = @tweet_list.count
  end
end
