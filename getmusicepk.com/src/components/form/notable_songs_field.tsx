import { set } from 'firebase/database';
import { useEffect, useState } from 'react';

const inputRow = ({
  songGetter,
  songSetter,
  playGetter,
  playSetter,
  index,
  error,
}) => (
  <div className="flex flex-col md:flex-row w-full md:items-center justify-center p-2" key={`song-row-${index}`}>
    <label className="flex w-[60%] items-center gap-6">
      <span className="font-semibold text-white">song</span>
      <input
        type="text"
        name={`notableSongs-${index}-title`}
        placeholder={`type here...`}
        value={songGetter}
        onChange={(event) => songSetter(event.target.value)}
        className={`white_placeholder flex-grow appearance-none rounded ${error ? 'border-2 border-red-500' : ''
          } bg-[#63b2fd] px-4 py-2 leading-tight text-white focus:bg-white font-semibold focus:text-black focus:outline-none`}
      />
    </label>
    <div className='h-2 md:w-4'/>
    <label className="flex w-[60%] items-center gap-6">
      <span className="font-semibold text-white">plays</span>
      <input
        type="number"
        name={`notableSongs-${index}-plays`}
        placeholder={`type here...`}
        value={playGetter}
        onChange={(event) => playSetter(event.target.value)}
        className={`white_placeholder flex-grow appearance-none rounded ${error ? 'border-2 border-red-500' : ''
          } bg-[#63b2fd] px-4 py-2 leading-tight text-white focus:bg-white font-semibold focus:text-black focus:outline-none`}
      />
    </label>
  </div>
);

const NotableSongsField = ({ formData, updateFormData, onValidation, user }: {
  formData: { [key: string]: any },
  updateFormData: any,
  onValidation: any,
  user: any
}) => {
  const [error, setError] = useState<string | null>(null);
  const [notableSong1, setNotableSong1] = useState<string>('');
  const [notableSong2, setNotableSong2] = useState<string>('');
  const [notableSong3, setNotableSong3] = useState<string>('');
  const [plays1, setPlays1] = useState<number>(0);
  const [plays2, setPlays2] = useState<number>(0);
  const [plays3, setPlays3] = useState<number>(0);

  // const validateForUI = (value) => {
  //   if (value.length === 0) {
  //     setError('Fields cannot be empty');
  //     onValidation(false);
  //   } else {
  //     setError(null);
  //     onValidation(true);
  //   }
  // };

  useEffect(() => {
    if (formData['notableSongs']) {
      const { notableSongs } = formData;
      if (notableSongs.length > 0) {
        setNotableSong1(notableSongs[0].title);
        setPlays1(notableSongs[0].plays);
      }
      if (notableSongs.length > 1) {
        setNotableSong2(notableSongs[1].title);
        setPlays2(notableSongs[1].plays);
      }
      if (notableSongs.length > 2) {
        setNotableSong3(notableSongs[2].title);
        setPlays3(notableSongs[2].plays);
      }
    }
  }, []);

  const justValidate = (value) => {
    if (value.length === 0) {
      onValidation(false);
    } else {
      onValidation(true);
    }
  };

  useEffect(() => {
    justValidate(notableSong1);
    justValidate(notableSong2);
    justValidate(notableSong3);
    updateFormData({
      ...formData,
      notableSongs: [
        { title: notableSong1, plays: plays1 },
        { title: notableSong2, plays: plays2 },
        { title: notableSong3, plays: plays3 }
      ]
    });
  }, [
    notableSong1,
    notableSong2,
    notableSong3,
    plays1,
    plays2,
    plays3,
  ]);

  return (
    <div className="page flex h-full flex-col items-center justify-center">
      <div className="flex w-full flex-col items-start">
        <h1 className="mb-2 text-2xl font-bold text-white">
          What are your most streamed songs?
        </h1>
        {[
          {
            songGetter: notableSong1,
            songSetter: setNotableSong1,
            playsGetter: plays1,
            playsSetter: setPlays1,
          },
          {
            songGetter: notableSong2,
            songSetter: setNotableSong2,
            playsGetter: plays2,
            playsSetter: setPlays2,
          },
          {
            songGetter: notableSong3,
            songSetter: setNotableSong3,
            playsGetter: plays3,
            playsSetter: setPlays3,
          }
        ].map(({ songGetter, songSetter, playsGetter, playsSetter }, index) => {
          return inputRow({
            songGetter,
            songSetter,
            playGetter: playsGetter,
            playSetter: playsSetter,
            index,
            error,
          })
        })}
        {error && <p className="mt-2 text-red-500">{error}</p>}
      </div>
    </div>
  );
};

export default NotableSongsField;
