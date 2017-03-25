require 'twitter'
require 'stemmer'
require 'lingua/stemmer'
require'sentimental'
require 'config_dev'
require 'json'

if ConfigDev.PB_SSL
  require 'openssl'
  OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
end

class PagesController < ApplicationController

  THRESHOLD = 0.5
  LANGUAGE = "en"
  USELESS_WORD = /\s(a|an|the|this|that)\s/
  USELESS_PONCTUATION = /[,;:."-]/
  STEMMER = Lingua::Stemmer.new(:language => LANGUAGE)
  $negation_word = ["no","don't","didn't","won't","not","couldn't","can't","hate","dislike"]

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
    #@tweet_list =  prepare_tweets client.search(@keywords, lang: LANGUAGE)
    @tweet_list = JSON.parse(get_dataset)
    clean_tweets @tweet_list
    @nbTweets = @tweet_list.count #Nombre de tweets trouvés
    #Analyse sentimentale des tweets
    sentimental_and_score_analysis @tweet_list
    #Classification des tweets
    #set_dataset(@tweet_list)
    @matrice_score = initialisation(@nbTweets)
    make_class(@tweet_list, @matrice_score)
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
      #On rend la liste des tweets au format json
      res.to_json
  end

  #Fonction créant un dataset au format json avec le résultat de la requête
  def set_dataset(tweets)
    File.open("dataset.json", "w") do |f|
        f.write(tweets)
    end
  end

  #Fonction récupérant un dataset au format json
  def get_dataset()
      file = File.read("dataset.json")
  end


  #----- Nettoyage des tweets -----
  def clean_tweets(tweets) #
     tweets.each do |key, tweet|
        # 1.Downcase
        tweet["cleaned_text"] = tweet["text"].downcase
        # 2.Delete useless terms
        delete_useless_terms tweet["cleaned_text"]
        # 3.Stemmify
        tweet["cleaned_text"] = stemmify tweet["cleaned_text"]
     end
  end

  def stemmify(tweet) #Garde la racine des mots
    sample = tweet.split(/\s/)
    sample.map! do |term|
      STEMMER.stem(term)
    end
    sample.join(" ")
  end

  def delete_useless_terms(tweet) #Supprime les termes superflus
    tweet.gsub!(USELESS_WORD, " ") #Suppression des déterminants
    tweet.gsub!(USELESS_PONCTUATION, "") #Suppresion de la ponctuation
  end



  #----- Classification tweets -----

  def initialisation(n)
    res = Array.new(n) {|i| Array.new(n) {|j| -1} } # Create an empty tab (2 lin * 1 col) initialize with 0 (another way)
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
      #negation tweet
    end
    tweets
  end

  def word__comparaison_score(tweet1_string, tweet2_string)

    var = true
    tweet1 = tweet1_string.split(/\s/)
    tweet2 = tweet2_string.split(/\s/)

    cmpt = 0
    if(tweet1.length < tweet2.length)
      min = tweet1.length
      max = tweet2.length
    else
      min = tweet2.length
      max = tweet1.length
    end

    for i in (0..(min-1))
      var = true
      for j in (0..(max-1))
        if (tweet1[i]==tweet2[j] && var )
          cmpt+=1
          var = false
        end
      end
    end
    score = (((cmpt.to_f/min)+(cmpt.to_f/max))/2.to_f)
  end

  def result_score(score)
    score = case
    when (score<0.25) then "low"
    when ((0.25<= score) and (score<0.75)) then "neutral"
    when ((0.75 <= score) and (score<1)) then "high"
    when 1 then "equals"
    when 0 then "different"
    else "errror"
    end
    score
  end

  def negation(tweet_string)
    array = tweet_string.split(/\s/)
    for i in (0..(array.length-1))
      if $negation_word.include?(array[i])
        return "negatif"
      end
    end
    return "positif"
  end

  def make_class(tweets,matrice)
    long = tweets.length
    i = 0
    j = 0
    tweets.each do |key1,tweet1|
      #for i in (0..long)
      tweet1["negatif"] = negation(tweet1["cleaned_text"])
        j = 0
        tweets.each do |key2,tweet2|
        #for j in ((i+1)..(long-1))
          if(j>i)
            matrice[i][j] = Hash.new
            tmp = word__comparaison_score(tweet1["cleaned_text"], tweet2["cleaned_text"])
            matrice[i][j]["score"] = tmp
            matrice[i][j]["value"] = result_score(tmp)
          end
          j+=1
        end
        i+=1
      end
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
