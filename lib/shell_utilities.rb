# Basic shell I/O methods

#TODO: Add color helpers for *nix platforms


# Should be pretty cross-platform
def clear_screen
  Gem.win_platform? ? system("cls") : system("clear")
end


# Prompt the user for input, optionally with choices and a default.
def prompt(text, choices=[], default=nil)
  # Prompt text 
  #  -- or: --
  # Prompt text  (default: value)
  # > 
  #  -- or: --
  # Prompt text  (default: value)
  # Choices: [list, shown, here]
  # > 

  has_choices = choices.present?
  has_default = default.present?

  prompt_text  = text
  prompt_text += "  (default: #{default})"  if has_default

  choice_text = ""
  choice_text = "choices: [#{choices.join(", ")}]"  if has_choices


  printf prompt_text
  if (has_choices)
    printf "\n"
    printf choice_text
  end

  printf "\n>"  if (has_choices || has_default)
  printf " "


  # `Kernel::gets` reads from `argv` first, and tries opening args as filenames.  Do not want!
  choice = STDIN::gets.chomp

  # Default value
  unless default.nil?
    return default  if choice.empty?
  end

  # Restart if there are choices, but the input is not among them
  if choices.present?
    unless choices.include?(choice)
      printf "Invalid choice.\n\n"
      # wtb real tail-calls :<
      choice = prompt(text, choices, default)
    end
  end

  choice
end
