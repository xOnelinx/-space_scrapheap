package com.mygdx.game;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.math.Vector2;

/**
 * Created by Денис on 22.01.2017.
 */

 public class InputHander {

    public static boolean isClicked() {
        return Gdx.input.justTouched();
    }
    public static boolean isPressed() {
        return Gdx.input.isTouched();
    }
    public static Vector2 getMousePoz() {
        return new Vector2(Gdx.input.getX(),Gdx.graphics.getHeight()-Gdx.input.getY());
    }
}
