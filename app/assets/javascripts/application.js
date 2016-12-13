// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery
//= require jquery_ujs
//= require bootstrap.min
//= require turbolinks
//= require_tree .


function home_size(){
  var h = $(window).height();
  $('.home').height(h);
  $('.home').css('line-height',h+'px');
}

function highlight_keywords(){
  compt=0;
  keywords_list = $('#keywords_list b')[0].innerHTML.split(" ");
  $('.tweet_content').each(function(){
    keywords_list.forEach(function(keyword){
      var regEx = new RegExp(keyword, "ig");
      $('.tweet_content')[compt].innerHTML = $('.tweet_content')[compt].innerHTML.replace(regEx,"<span class=\"keyword\">$&</span>");
    });
    compt++;
  });
}

$('.tweet').ready(function(){
  highlight_keywords();
})

$(document).ready(function(){
  home_size();
});

$(window).resize(function(){
  home_size();
});
