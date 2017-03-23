require 'twitter'
require 'stemmer'
require'sentimental'
require 'config_dev'
require 'json'

if ConfigDev.PB_SSL
  require 'openssl'
  OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
end

class PagesController < ApplicationController

  THRESHOLD = 0.5
    
  def init
    client = Twitter::REST::Client.new do |config|
      config.consumer_key = ConfigDev.CONSUMER_KEY
      config.consumer_secret = ConfigDev.CONSUMER_SECRET
      config.access_token = ConfigDev.ACCESS_TOKEN
      config.access_token_secret = ConfigDev.ACCESS_TOKEN_SECRET
    end
  end

  def search_tweets
    client = init
    @keywords = params[:keywords] ||= "test"
    #Si la liste de mots-clés est vide, Twitter API renvoie une erreur
    if @keywords=="" then @keywords = "test" end
    #Nettoyage des tweets
    #@tweet_list =  prepare_tweets client.search(@keywords, lang: "en")
    #clean_tweets @tweet_list
    @tweet_list = JSON.parse(get_dataset)
    @nbTweets = @tweet_list.count #Nombre de tweets trouvés
    #Analyse sentimentale des tweets
    @tweet_list = sentimental_and_score_analysis @tweet_list
    #Classification des tweets
    #set_dataset(@tweet_list)
  end

  def prepare_tweets(tweets)
      res = Hash.new
      tweets.each do |tweet|
        #Les tweets retournés par l'API sont en mode frozen, ils ne sont pas modifiables
        #Il faut donc récupérer une copie (.dup) de chaque attribut pour pouvoir les modifier
        res[tweet.id] = Hash.new
        res[tweet.id]["favorite_count"] = tweet.favorite_count.to_s
        res[tweet.id]["retweet_count"] = tweet.retweet_count
        res[tweet.id]["source"] = tweet.source.dup
        res[tweet.id]["attrs"] = tweet.attrs.dup
        res[tweet.id]["user"] = tweet.user.dup
        res[tweet.id]["in_reply_to_id"] = tweet.in_reply_to_user_id
        res[tweet.id]["text"] = tweet.text.dup
        res[tweet.id]["cleaned_text"] = ""
        res[tweet.id]["sentimental_class"] = "default"
        res[tweet.id]["sentimental_score"] = 0
      end
      res.to_json
  end
      
  def clean_tweets(tweets)
     tweets.each do |key, tweet|
        #1.Downcase  2.Rootify  (3.Delete useless terms)
        tweet["cleaned_text"] = stemmify tweet["text"].downcase
     end
  end
      
  #Fonction créant un dataset avec le résultat de la requête
  def set_dataset(tweets)
    File.open("dataset.json", "w") do |f|
        f.write(tweets)
    end 
  end
      
  def get_dataset()
      file = File.read("dataset.json")
  end

  def stemmify(tweet)
    token = tweet.split(" ")
    token.map! do |term|
      term.stem
    end
    token.join(" ")
  end

  def sentimental_class(text)
    analyzer = Sentimental.new
    analyzer.load_defaults
    analyzer.threshold = THRESHOLD
    analyzer.sentiment text
  end

  def sentimental_score(text)
    analyzer = Sentimental.new
    analyzer.load_defaults
    analyzer.threshold = THRESHOLD
    analyzer.score text
  end



  def sentimental_and_score_analysis(tweets)
    tweets.each do |key,tweet|
      tweet["sentimental_class"] = sentimental_class tweet["text"]
      tweet["sentimental_score"] = sentimental_score tweet["text"]
    end
    tweets
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