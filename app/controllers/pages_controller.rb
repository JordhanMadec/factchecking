require 'twitter'
require 'stemmer'
require'Sentimental'

class PagesController < ApplicationController
  def init
    client = Twitter::REST::Client.new do |config|
      config.consumer_key = "xpg49pUpKolcCXWuQe2b0EqYx"
      config.consumer_secret = "aqMRdUn28HqZrD1IIeXK6Pk0SfliFQGDuplBkZnlVo4cMvyaHo"
      config.access_token = "720567318443634689-4K5Xns30llMvExfUZG1IaBFrIqUe32q"
      config.access_token_secret = "hp31Ax4ZzAjaMikgsOwjHidqVhxxeE3kGDnBS6QT2Vo2K"
    end
  end

  def search_tweets
    client = init
    @keywords = params[:keywords] ||= "test"
    #Si la liste de mots-clés est vide, Twitter API renvoie une erreur
    if @keywords=="" then @keywords = "test" end
    #Nettoyage des tweets
    @tweet_list =  clean_tweets client.search(@keywords, lang: "en")
    @nbTweets = @tweet_list.count #Nombre de tweets trouvés
  end

  def clean_tweets(tweets)
      res = Hash.new
      tweets.each do |tweet|
        #Les tweets retournés par l'API sont en mode frozen, ils ne sont pas modifiables
        #Il faut donc récupérer une copie (.dup) de chaque attribut pour pouboir les modifier
        res[tweet.id] = Hash.new
        res[tweet.id]["favorite_count"] = tweet.favorite_count.to_s
        res[tweet.id]["retweet_count"] = tweet.retweet_count
        res[tweet.id]["source"] = tweet.source.dup
        res[tweet.id]["attrs"] = tweet.attrs.dup
        res[tweet.id]["user"] = tweet.user.dup
        res[tweet.id]["in_reply_to_id"] = tweet.in_reply_to_user_id
        res[tweet.id]["text"] = tweet.text.dup
        #1.Downcase  2.Rootify  3.Delete useless terms
        res[tweet.id]["cleaned_text"] = stemmify tweet.text.dup.downcase
      end
      res
  end

  def stemmify(tweet)
    token  = tweet.split(" ")
    token.map! do |term|
      term.stem
    end
    token.join(" ")
  end

  #@tweet_list = ["I like cat","I hate dog","I love ice cream"]
  $tweet_list_class =[]
  $THRESHOLD = 0.5

  def make_tweet_class
    @tweet_list.each do |tweet|
      tweet_class = Tweet.new tweet.text
      $tweet_list_class.push(tweet_class)
    end
  end

  def make_tweet_sentimental
    $tweet_list_class.each do |tweet|
      tweet.sentimental_class
    end
  end

  def make_tweet_score
    $tweet_list_class.each do |tweet|
      tweet.sentimental_score
    end
  end


  class Tweet

    attr_accessor :tweet_class, :tweet_text, :tweet_score

    def initialize(text)
      @tweet_text = text

    end


    def sentimental_class

      analyzer = Sentimental.new
      analyzer.load_defaults
      analyzer.threshold = $THRESHOLD
      #puts analyzer.sentiment tweet_text
      @tweet_class = analyzer.sentiment tweet_text
    end

    def sentimental_score

      analyzer = Sentimental.new
      analyzer.load_defaults
      analyzer.threshold = $THRESHOLD
      @tweet_score = analyzer.score tweet_text
      #puts analyzer.score tweet_text

    end
  end





  def pre_classification(tweets)
    #Preclassification des tweets
  end

  def weigh(tweets)
    #Pondération des tweets
  end

  def score_classes(tweets)
    #Score les différentes classes
  end
end
