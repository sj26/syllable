require "dbm"
require "humanize"

# Large portions from http://www.pressure.to/ruby/

module Syllable extend self
  def words text
    text.scan(/\b([a-z][a-z'-]*)|(?:(\$?)\s*((?:\.?\d+,?)+))\b/i).flat_map do |word, dollar, number|
      if word
        word.sub(/(?:'s|s')\Z/, "s")
      elsif number
        number = number.gsub(/\D+/, "").to_i
        number.humanize.split(/\s+/).tap do |words|
          words << "dollar" unless dollar.empty?
        end
      end
    end
  end

  def dictionary
    @dictionary ||= DBM.new(File.expand_path("../syllable/dictionary-dbm", __FILE__)).tap do |dbm|
      if dbm.keys.length.zero?
        IO.foreach(File.expand_path('../syllable/dictionary', __FILE__)) do |line|
          next if line !~ /^[A-Z]/
          line.chomp!
          (word, *phonemes) = line.split(/  ?/)
          dbm.store word, phonemes.grep(/^[AEIOU]/).length
        end
      end
    end
  end

  # special cases - 1 syllable less than expected
  SubSyl = [
    /[^aeiou]e$/, # give, love, bone, done, ride ...
    /[aeiou](?:([cfghklmnprsvwz])\1?|ck|sh|[rt]ch)e[ds]$/,
    # (passive) past participles and 3rd person sing present verbs:
    # bared, liked, called, tricked, bashed, matched

    /.e(?:ly|less(?:ly)?|ness?|ful(?:ly)?|ments?)$/,
    # nominal, adjectival and adverbial derivatives from -e$ roots:
    # absolutely, nicely, likeness, basement, hopeless
    # hopeful, tastefully, wasteful

    /ion/, # action, diction, fiction
    /[ct]ia[nl]/, # special(ly), initial, physician, christian
    /[^cx]iou/, # illustrious, NOT spacious, gracious, anxious, noxious
    /sia$/, # amnesia, polynesia
    /.gue$/ # dialogue, intrigue, colleague
  ]

  # special cases - 1 syllable more than expected
  AddSyl = [
    /i[aiou]/, # alias, science, phobia
    /[dls]ien/, # salient, gradient, transient
    /[aeiouym]ble$/, # -Vble, plus -mble
    /[aeiou]{3}/, # agreeable
    /^mc/, # mcwhatever
    /ism$/, # sexism, racism
    /(?:([^aeiouy])\1|ck|mp|ng)le$/, # bubble, cattle, cackle, sample, angle
    /dnt$/, # couldn/t
    /[aeiou]y[aeiou]/ # annoying, layer
  ]

  # special cases not actually used - these seem to me to be either very
  # marginal or actually break more stuff than they fix
  NotUsed = [
    /^coa[dglx]./, # +1 coagulate, coaxial, coalition, coalesce - marginal
    /[^gq]ua[^auieo]/, # +1 'du-al' - only for some speakers, and breaks
    /riet/, # variety, parietal, notoriety - marginal?
  ]

  # Uses english word patterns to guess the number of syllables. A single module
  # method is made available, +syllables+, which, when passed an english word,
  # will return the number of syllables it estimates are in the word.
  # English orthography (the representation of spoken sounds as written signs) is
  # not regular. The same spoken sound can be represented in multiple different
  # ways in written English (e.g. rough/cuff), and the same written letters
  # can be pronounced in different ways in different words (e.g. rough/bough).
  # As the same series of letters can be pronounced in different ways, it is not
  # possible to write an algorithm which can always guess the number of syllables
  # in an english word correctly. However, it is possible to use frequently
  # recurring patterns in english (such as "a final -e is usually silent") to
  # guess with a level of accuracy that is acceptable for applications like
  # syllable counting for readability scoring. This module implements such an
  # algorithm.
  # This module is inspired by the Perl Lingua::EN::Syllable module. However, it
  # uses a different (though not larger) set of patterns to compensate for the
  # 'special cases' which arise out of English's irregular orthography. A number
  # of extra patterns (particularly for derived word forms) means that this module
  # is somewhat more accurate than the Perl original. It also omits a number of
  # patterns found in the original which seem to me to apply to such a small number
  # of cases, or to be of dubious value. Testing the guesses against the Carnegie
  # Mellon Pronouncing Dictionary, this module guesses right around 90% of the
  # time, as against about 85% of the time for the Perl module. However, the
  # dictionary contains a large number of foreign loan words and proper names, and
  # so when the algorithm is tested against 'real world' english, its accuracy
  # is a good deal better. Testing against a range of samples, it guesses right
  # about 95-97% of the time.
  def guess word
    return 1 if word.length == 1
    word = word.downcase.delete("'")

    syllables = word.scan(/[aeiouy]+/).length

    # special cases
    for pat in SubSyl
      syllables -= 1 if pat.match(word)
    end
    for pat in AddSyl
      syllables += 1 if pat.match(word)
    end

    syllables = 1 if syllables < 1 # no vowels?
    syllables
  end

  def count_word word
    dictionary.fetch(word.upcase).to_i
  rescue IndexError
    guess word
  end

  def count text
    words(text).map(&method(:count_word)).reduce(0, &:+)
  end
end


if ARGV.delete("--spec")
  require "rspec/autorun"

  `rm dictionary-dbm*`

  describe Syllable do
    describe "#words" do
      specify { Syllable.words("An old silent pond...").should == ["An", "old", "silent", "pond"] }
      specify { Syllable.words("others' attitudes are, you").should == ["others", "attitudes", "are", "you"] }
      specify { Syllable.words("1! 2? 3^ 4* 5()").should == ["one", "two", "three", "four", "five"] }
      specify { Syllable.words("Didn't won't aren't bad").should == ["Didn't", "won't", "aren't", "bad"] }
      specify { Syllable.words("$2 soda\nin 2012").should == ["two", "dollar", "soda", "in", "two", "thousand", "and", "twelve"] }
    end

    describe "#count_word" do
      specify { Syllable.count_word("soda").should == 2 }
      specify { Syllable.count_word("attitudes").should == 3 }
      specify { Syllable.count_word("don't").should == 1 }
      specify { Syllable.count_word("Springbok").should == 2 }
    end

    describe "#count" do
      specify do
        Syllable.count(<<-EOS).should == 17
          An old silent pond...
          A frog jumps into the pond,
          splash! Silence again.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          The Heartbreak Hotel
          May its register stay blank
          Till my next visit.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          If a wish comes true
          Who do you thank for this feat?
          Yourself for wishing.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Springbok, gnu, gazelle
          Slaking their thirst in dawn's light
          Bent low to water
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          African jungle
          King of Beasts prowls on his search
          Hungry for fresh meat
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Instant death stalking
          Uncertainty grips the herd
          Nervous hooves shuffle
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Lion creeps closer
          Saliva dripping from fangs
          Anticipation
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Sentinel bird shrieks
          All flee at the same instant
          Stampede on the Veldt.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Leaves drift down like boats
          on a green to and fro sea
          Winter approaches.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          The black panther waits
          unseen in leafy shadows
          Small faun draws nearer.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Morning rush for train
          Sad faces never smiling
          Why do they worry?
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Daily toil for all
          Lunchtime gossip backstabbing
          Then return to work
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Home to young faces
          No time for play...must work yet
          Someone has to earn
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Children grow quickly
          Independence, ho! beckons
          Babies leave the nest
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Lie in bed alone
          Thinking of love now long dead
          Was it all for naught?
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          after summer's rain 
          God's promise is remembered 
          glorious rainbow
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          People united 
          To secure their liberty 
          Out of many, one
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Ire's crest: David's Harp 
          Spring words 'Aaron Forever' 
          Covenants of God
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Fighting for freedom, 
          Fall of valiant soldier 
          Resting in the Lord
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Patrick of England 
          Preserving Erin's blood line 
          Drove out the serpents
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          'My sheep hear My voice' 
          Christ did say, 'and I know them 
          and they follow Me'
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Do NOT partake of 
          Knowledge of good and evil 
          Satan's fruit, broad lies
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Haiku will wake you 
          Dullsville in brain sharpen quick 
          Haiku no fake who.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Butterfly in class 
          learns lessons along with kids. 
          Excellent student.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          First autumn morning:
          the mirror I stare into
          shows my father's face.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          A giant firefly:
          that way, this way, that way, this -
          and it passes by.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Rainbow in the sky
          Inspiration of nature
          Relief from the storm
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Echoing mountains
          Endless possibilities
          God's gift to the earth
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Lie in bed alone
          Thinking of love now long dead
          Was it all for naught?
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Spheres of captured light
          Tales of life's contradictions
          Spectrum of the earth
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Trees reach to the sky
          As if grasping for God's hands
          Earth, heaven unite
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Wind blows, seagulls sing
          The waves crash upon the shore
          Earth, sea unite. BATCH!
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Spheres of captured light
          Tales of life's contradictions
          Spectrum of the earth
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Glistening waters
          Heaven's glorious showers
          Replenish the earth
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          So peaceful and still
          Tranquility takes over
          Peace rules the night's air
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Innocent raccoons
          Such gentle eyes, fragile lives
          Sit still, watch them play
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Homeless dog crying
          Why are humans oft cruel
          Innocent victim
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Spoken words of love
          They are my heart's warm sunshine
          Brighten up my day
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Be my friend today
          I can't promise you the stars
          We will share my heart
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Two species, one place
          Life's journeys so different
          No prejudice here
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Exotic island
          Wild dreams of passion and fun
          Escape from the world
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Desolate and dry
          Yearning for water, for life
          God will speak and heal
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Leaves of orange flame
          Autumn's magical embrace
          Nature's spice of life
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Vine weeps of sadness
          Maroon leaves sigh tears of pain
          Nightmare camouflaged
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Winding trail through time
          Blurred images of my past
          Life's moments relived
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Compassion is good
          Compassionate is better
          Life's moments relived
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          $2 soda
          Blurred images of my past
          Life's moments relived
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Sikkim, India, 
          on December 21, 
          2010.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Then no matter what 
          others' attitudes are, you 
          can keep inner peace.
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Didn't won't aren't bad 
          mustn't butt into convos
          1! 2? 3^ 4* 5()
        EOS
      end

      specify do
        Syllable.count(<<-EOS).should == 17
          Sacred gaffe homeless
          Else year friend buy taste york piece
          no diabetes
        EOS
      end
    end
  end
end
