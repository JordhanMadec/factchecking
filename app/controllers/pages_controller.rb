require 'twitter'
require 'stemmer'
require 'lingua/stemmer'
require 'sentimental'
require 'config_dev'
require 'json'
require 'uri'
require 'date'

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
  NEGATION_WORD = ["no","don't","didn't","won't","not","couldn't","can't","hate","dislike"]

  NB_CLASSES = 10
  BONUS = 1.2
  MALUS = 0.8


  # Pour la pondération

  @@abo = Array.new
  @@rtf = Array.new
  @@avg_abo = 0
  @@avg_rft = 0
  @@median_abo = 0
  @@median_rft = 0
  # Pour le temps de propagation
  @@dates = Array.new
  @@borne_gauche = -1
  @@borne_droite = -1

  $classe_max_personne = 0
  $classe_min_personne = 0
  $classe_rpz_mieux = 0
  $classe_rpz_mal = 0

  $keywords_sentimental = "neutral"
  $keywords_negatif = "neutral"


  #Tableau avec le numéro de tour de boucle
  @@key = Array.new

  #Tableau avec le nombre de classe de tweets que l'on veut pour la comparaison mot à mot (appeler la méthode init_nb_class)
  $classe = Array.new

  $stats = { retweets: 0,
             favs: 0,
             first_tweet_date: nil,
             touched_people: 0,
             propagation_time: 0,
             negative_count: 0,
             neutral_count: 0,
             positive_count: 0,
             true_count: 0,
             false_count: 0 }

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
    puts 'Client init'

    @keywords = params[:keywords] ||= "test"

    #Si la liste de mots-clés est vide, Twitter API renvoie une erreur
    if @keywords=="" then @keywords = "test" end

    puts 'Keywords: ' + @keywords

    #Nettoyage des tweets
    puts Time.now.strftime("%H:%M:%S") + ' Reaching tweets...'
    @tweet_list = JSON.parse(prepare_tweets client.search(@keywords, lang: LANGUAGE))
    #@tweet_list = JSON.parse(get_dataset)
    puts Time.now.strftime("%H:%M:%S") + ' Tweets reached'
    @nbTweets = @tweet_list.count #Nombre de tweets trouvés
    puts Time.now.strftime("%H:%M:%S") + " Tweets found: #{@nbTweets}"

    puts Time.now.strftime("%H:%M:%S") + ' Saving dataset'
    set_dataset(@tweet_list)

    puts Time.now.strftime("%H:%M:%S") + ' Creating nb classes tweets'
    init_nb_class(NB_CLASSES)

    #creation de la matrice de score
    puts Time.now.strftime("%H:%M:%S") + ' Creating scores matrice'
    @matrice_score = initialisation(@nbTweets)

    #trie des dates
    puts Time.now.strftime("%H:%M:%S") + ' Sort dates'
    @@dates.sort!

    #cleaned_text, sentimental_and_score_analysis, make_class
    puts Time.now.strftime("%H:%M:%S") + ' First loop'
    main_1(@tweet_list, @matrice_score)

    puts Time.now.strftime("%H:%M:%S") + ' Init weight'
    init_weigh()

    puts Time.now.strftime("%H:%M:%S") + ' Second loop'
    main_2(@tweet_list, @matrice_score)


    puts Time.now.strftime("%H:%M:%S") + ' Third loop'
    main_3(@tweet_list, @matrice_score)


    puts Time.now.strftime("%H:%M:%S") + ' Propagation time'
    date_diff = ( Time.at(@@dates[@@borne_droite]) - Time.at(@@dates[@@borne_gauche])).to_f
    date_diff_unite = "sec"
    if date_diff > 60 then
      date_diff = date_diff / 60
      date_diff_unite = "min"
      if date_diff > 60 then
        date_diff_unite = "h"
        date_diff = date_diff / 60
      end
    end
    $stats[:propagation_time] = (date_diff.round(2).to_s + date_diff_unite)
    puts $stats[:propagation_time]


    @false_class = { score: 0,
                     nb_tweets: 0,
                     population: Array.new}
    @true_class = { score: 0,
                    nb_tweets: 0,
                    population: Array.new}

    puts Time.now.strftime("%H:%M:%S") + ' Analyse main_3...'
    analyse_function_classe(@nbTweets, @keywords, @tweet_list)

    puts Time.now.strftime("%H:%M:%S") + ' Scoring class...'
    score_classes(@true_class, @false_class, @tweet_list, @matrice_score)

    puts Time.now.strftime("%H:%M:%S") + ' Finished !'

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

        # Pour le temps de propagation
        @@dates.push(DateTime.parse(res[tweet.id]["attrs"][:created_at]).to_time.to_i)

        #Preparing stats
        $stats[:retweets] += tweet.retweet_count
        $stats[:favs] += tweet.favorite_count
        $stats[:touched_people] += tweet.user.followers_count
      end
      #On rend la liste des tweets au format json
      res.to_json
  end

  #Fonction créant un dataset au format json à partir d'une liste de tweets
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
  def clean_tweet(tweet) #Nettoie les tweets
    # 1.Downcase
    tweet["cleaned_text"] = tweet["text"].downcase
    # 2.Delete useless terms
    delete_useless_terms tweet["cleaned_text"]
    # 3.Stemmify
    tweet["cleaned_text"] = stemmify tweet["cleaned_text"]
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

  def init_nb_class(n)
    for i in (0..(n-1))
      $classe.push(Array.new)
    end
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

  def sentimental_and_score_analysis(tweet)
    tweet["sentimental_class"] = sentimental_class tweet["text"]
    tweet["sentimental_score"] = sentimental_score tweet["text"]

    #Preparing stats
    if (tweet["sentimental_class"].to_s == "negative") then
      $stats[:negative_count] += 1
    elsif (tweet["sentimental_class"].to_s == "neutral") then
      $stats[:neutral_count] += 1
    else
      $stats[:positive_count] += 1
    end

    tweet
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

    when ((0<score) and (score<0.25)) then "low"
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
      if NEGATION_WORD.include?(array[i])
        return "negatif"
      end
    end
    return "positif"
  end

  def make_class(tweet,num_Tweet,matrice, tweets_list)
    tweet1 = tweet
    i = num_Tweet
    j = 0
    tweet1["negatif"] = negation(tweet1["cleaned_text"])
    j = 0
        tweets_list.each do |key2,tweet2|
          if(j>i)
            matrice[i][j] = Hash.new
            tmp = word__comparaison_score(tweet1["cleaned_text"], tweet2["cleaned_text"])
            matrice[i][j]["score"] = tmp
            matrice[i][j]["value"] = result_score(tmp)
            matrice[i][j]["id_tweet"] = key2
          end
          j+=1
        end
  end


  def classes(matrice_score, tweet, id_tweet, num_tweet,nb_tweets, num_classe)
    cmpt = num_classe
    j = num_tweet + 1
    if cmpt < ($classe.length)
      if (num_tweet+1) < nb_tweets
        $classe[cmpt].push(id_tweet)
      for i in j..nb_tweets
        if( !@@key.empty?) then
          if @@key.include?(i)
            if(matrice_score[num_tweet][i]["score"] > 0.3)
              $classe[cmpt].push(matrice_score[num_tweet][i]["id_tweet"])
              @@key.delete(i)

            end
          end
        else
          break
        end
      end
    end
  end
  end

  def analyse_function_classe(nb_tweets, keyword, tweet_list)
    $keywords_sentimental = sentimental_class keyword
    $keywords_negatif = negation keyword
    max = 0
    min = nb_tweets
    best = -1
    worst = 2
    for i in 0..(NB_CLASSES-1)
      if !$classe[i].empty?
      #determine la calsse avec le plus grand nombre de tweet et le plus petit nombre
      if $classe[i].count > max then
        max = $classe[i].count
        $classe_max_personne = i
      else
        if $classe[i].count < min
          min = $classe[i].count
          $classe_min_personne = i
        end
      end
      #determine la classe la plus représentative et la moins représentative des mots de la recherche
      puts $classe[i][0]
      tweet = tweet_list[$classe[i][0]]
      puts keyword
      #puts tweet["cleaned_text"]
      tmp = word__comparaison_score(keyword, tweet["cleaned_text"])
      if  tmp > best then
        best = tmp
        $classe_rpz_mieux = i
      else
        if tmp < worst
          worst = tmp
          $classe_rpz_mal = i
        end
      end
    end
  end
  end




  # return vrai si l'utilisateur est blackliste
  def isBlacklisted(id)
    file = File.read("blacklist.txt")
    file.gsub!(/\r\n?/, "\n")
    file.each_line do |line|
      if line.to_s == id.to_s
        return true
      end
    end
    return false
  end

  # renvoie 1 si good news, -2 si fake news, 0 sinon
  def statutURLs(urls)
    urls.each do |url|

      uri_host = URI.parse(URI.encode(url["expanded_url"])).host

      # vérifie si fake news
      file = File.read("fake_news.txt")
      file.gsub!(/\r\n?/, "\n")
      file.each_line do |line|
        if line == uri_host
          return (-2)
        end
      end

      # vérifie si good news
      file = File.read("good_news.txt")
      file.gsub!(/\r\n?/, "\n")
      file.each_line do |line|
        if line == uri_host
          return 1
        end
      end

    end
    return 0
  end

  def median(array)
    sorted = array.sort
    len = sorted.length
    (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
  end

  def init_weigh()
    # Medianes...
    @@median_abo = median(@@abo)
    @@median_rft = median(@@rtf)

    # Moyennes...
    @@avg_abo = @@abo.inject(:+).to_f / @@abo.length
    @@avg_rft = @@rtf.inject(:+).to_f / @@rtf.length


    # Infos pour dev
    puts "MEDIANE ABO: #{@@median_abo}"
    puts "AVG ABO: #{@@avg_abo}"
    puts "MEDIANE RFT: #{@@median_rft}"
    puts "AVG RFT: #{@@avg_rft}"
  end

  def weigh(t)
    # Pondération des tweets
    # Importance de chaque critère :
=begin
    1. Auteur blacklisté ou non      - check si user.id est blacklisté, on néglige alors
    2. Présence d’une URL ou non     - si expanded_url pointe vers un site de fake news,
                                       on néglige le tweet, si pointe vers good news, on le met devant
                                       sinon neutre (on fait rien)
    3. Popularité                    - on se base sur la médiane&moyenne des rt fav et du nb abo
=end
    # Pondération...
        t_rtf = Integer(t["retweet_count"]) + Integer(t["favorite_count"])
        t_abo = Integer(t["user"]["followers_count"])

        # urls
        t["weight"] = statutURLs(t["attrs"]["entities"]["urls"])

        # blacklist
        if isBlacklisted(t["user"]["id"])
          t["weight"] -= 2
        else

        # médianes : rt&fav + abo
        if t_rtf>100 && t_rtf > @@median_rft

            t["weight"] += 0.1

            if t_abo>300 && t_abo > @@median_abo
              t["weight"] += 0.1
            end

            # moyennes : rt&fav + abo
            t["weight"] += (t_rtf > @@avg_rft ? 0.2 : 0 ) + (t_abo  > @@avg_abo ? 0.1 : 0 )

            # hashtags
            if !t["attrs"]["entities"]["hashtags"].empty?
              ht = []
              t["attrs"]["entities"]["hashtags"].each do |h|
                ht.push(h["text"])
              end
              t["weight"] += (t["cleaned_text"].split(" ") & ht).empty? ? 0.1 : 0
            end
        end
        t["weight"].round(2)
    end
  end


  #--------1er tour de boucle -----------------
  def main_1(tweets_list)

    # Pour date
    i = 0
    min = (2**(0.size * 8 -2) -1)
    n = @@dates.length
    m = n * 0.35 #35%

    tweets_list.each do |key, tweet|
      clean_tweet tweet
      sentimental_and_score_analysis tweet

      # Pour date
      if i < (n-m) then
        tmp = @@dates[i+m] - @@dates[i]
        if tmp <= min then
          min = tmp
          @@borne_gauche = i
        end
      end
      i = i + 1

      # Pour la pondération
      @@rtf.push(Integer(tweet["retweet_count"]) + Integer(tweet["favorite_count"]))
      @@abo.push(Integer(tweet["user"]["followers_count"]))
      @@key.push(i)
      i += 1
    end
  end

  #--------2ème tour de boucle -----------------
  def main_2(tweets_list, matrice_score)

    # Pour date
    min = (2**(0.size * 8 -2) -1)
    n = @@dates.length
    i = n-1
    m = n * 0.35 #35%

    num_Tweet = 0
    tweets_list.each do |key, tweet|
      make_class(tweet, num_Tweet, matrice_score, tweets_list)
      weigh tweet

      # Pour date
      if i > m then
        tmp = @@dates[i] - @@dates[i-m]
        if tmp <= min then
          min = tmp
          @@borne_droite = i
        end
      end
      i = i - 1

      num_Tweet +=1
    end
  end

  #---------3ème tour de boucle ---------------------

  def main_3(tweets_list, matrice_score)
    num_Tweet = 0
    tweets_list.each do |key, tweet|
    classes(matrice_score, tweet, key, num_Tweet, tweets_list.length, num_Tweet)
      num_Tweet +=1
    end
  end

  #---------- Scoring classes ----------
  def score_classes(true_class, false_class, tweets, matrice)
    #Score les différentes classes
    puts $keywords_sentimental
    tweets.each do |key, tweet|

        sen = tweet["sentimental_class"]
        neg = tweet["negatif"]


        if ((sen == "positive") && $keywords_sentimental = "positive") || (( sen == "negative") && $keywords_sentimental = "negative") || (( neg == "negatif") && $keywords_negatif = "negatif") then
          true_class[:population].push(tweet)
          true_class[:nb_tweets]++
          if $classe[$classe_rpz_mieux].include?(key) || $classe[$classe_max_personne].include?(key) then
            puts "positif"
          true_class[:score] += tweet['sentimental_score'].abs * (tweet['weight']+1)*BONUS
          else
            true_class[:score] += tweet['sentimental_score'].abs * (tweet['weight']+1)
          end

          $stats[:true_count] += 1
        else
          false_class[:population].push(tweet)
          false_class[:nb_tweets]++
          if $classe[$classe_rpz_mal].include?(key) || $classe[$classe_min_personne].include?(key) then
            puts "Negatif"
          false_class[:score] += tweet['sentimental_score'].abs * (tweet['weight']+1)*MALUS
          else
            false_class[:score] += tweet['sentimental_score'].abs * (tweet['weight']+1)
          end

          $stats[:false_count] += 1
        end

    end #end each
  end #end func

end
