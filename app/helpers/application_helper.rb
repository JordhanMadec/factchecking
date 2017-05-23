module ApplicationHelper
  include PagesHelper
  def link_to_image(image_path, target_link,options={})
    link_to(image_tag(image_path, :border => "0"), target_link, options)
  end

  def make_title(title='')
    title + ' | Twitter Fact Checker | INSA Rennes'
  end

  def get_path_for_search
    if current_page?(root_url)
      'pages/result'
    else
      'result'
    end
  end

  def render_fact_result(true_count, false_count)
    if true_count > false_count
      return '<button id="conclusion" type="button" class="btn btn-fresh text-uppercase btn-lg">
              <i class="fa fa-check-circle-o" aria-hidden="true"></i>&nbsp;True
             </button>
             <button type="button" class="btn btn-hot text-uppercase btn-lg disabled">False</button>
             <button type="button" class="btn btn-sunny text-uppercase btn-lg disabled">None</button>'
    else
      if true_count < false_count
        return '<button type="button" class="btn btn-fresh text-uppercase btn-lg disabled">True</button>
               <button id="conclusion" type="button" class="btn btn-hot text-uppercase btn-lg">
                <i class="fa fa-exclamation-triangle" aria-hidden="true"></i>&nbsp;False
               </button>
               <button type="button" class="btn btn-sunny text-uppercase btn-lg disabled">None</button>'
      else
        return '<button type="button" class="btn btn-fresh text-uppercase btn-lg disabled">True</button>
               <button type="button" class="btn btn-hot text-uppercase btn-lg disabled">False</button>
               <button id="conclusion" type="button" class="btn btn-sunny text-uppercase btn-lg">
                <i class="fa fa-question-circle" aria-hidden="true"></i>&nbsp;None
               </button>'
      end
    end
  end

  def bootstrap_class_for flash_type
    { success: "alert-success", error: "alert-danger", alert: "alert-warning", notice: "alert-info" }[flash_type] || flash_type.to_s
  end

  def flash_messages(opts = {})
    flash.each do |msg_type, message|
      concat(content_tag(:div, message, class: "alert #{bootstrap_class_for(msg_type)} fade in") do
        concat content_tag(:button, 'x', class: "close", data: { dismiss: 'alert' })
        concat message
      end)
    end
    nil
  end

end
